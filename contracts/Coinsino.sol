//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "hardhat/console.sol";

contract Coinsino is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public injectorAddress;
    address public operatorAddress;
    address public treasuryAddress;

    uint256 public currentLotteryId;
    uint256 public currentTicketId;

    uint256 public maxNumberOfTicketsPerBuyOrClaim = 1000;

    uint256 public maxPriceTicketInEther = 1000 ether;
    uint256 public minPriceTicketInEther = 3 ether;

    uint256 public pendingInjectionNextLottery;

    // temporary values
    uint256 public constant MIN_DISCOUNT_DIVISOR = 300;
    uint256 public constant MIN_LENGTH_LOTTERY = 30 seconds; // 5 minutes (set to 30 seconds for test purposes)
    uint256 public constant MAX_LENGTH_LOTTERY = 5 days + 5 minutes; // 5 days
    uint256 public constant MAX_TREASURY_FEE = 3000; // 30%

    enum Status {
        Pending,
        Open,
        Closed,
        Claimable
    }

    struct Lottery {
        Status status;
        uint256 startTime;
        uint256 endTime;
        uint256 priceTicketInEther;
        uint256 discountDivisor;
        uint256 treasuryFee; // 500: 5% // 200: 2% // 50: 0.5%
        uint256 firstTicketId;
        uint256 firstTicketIdNextLottery;
        uint256 amountCollectedInEther;
        uint256[6] rewardsBreakdown; // 0: 1 matching number // 5: 6 matching numbers
        uint256[6] etherPerPool;
        uint256[6] countWinnersPerPool;
        uint32 finalNumber;
    }

    struct Ticket {
        uint32 number;
        address owner;
    }

    // Mappings
    mapping(uint256 => Lottery) private _lotteries;
    mapping(uint256 => Ticket) private _tickets;

    // Pool calculator is used for verifying claims for ticket prizes
    mapping(uint32 => uint32) private _poolCalculator;

    // Keeps track of number of ticket per unique combination for each lotteryId
    mapping(uint256 => mapping(uint32 => uint256))
        private _numberTicketsPerLotteryId;

    // Keep track of user ticket ids for a given lotteryId
    mapping(address => mapping(uint256 => uint256[]))
        private _userTicketIdsPerLotteryId;

    modifier notProxy() {
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "Not operator");
        _;
    }

    modifier onlyOwnerOrInjector() {
        require(
            (msg.sender == owner()) || (msg.sender == injectorAddress),
            "Not owner or injector"
        );
        _;
    }

    event AdminTokenRecovery(address token, uint256 amount);
    event LotteryClosed(
        uint256 indexed lotteryId,
        uint256 firstTicketIdNextLottery
    );
    event LotteryInjection(uint256 indexed lotteryId, uint256 injectedAmount);
    event LotteryOpen(
        uint256 indexed lotteryId,
        uint256 startTime,
        uint256 endTime,
        uint256 priceTicketInEther,
        uint256 firstTicketId,
        uint256 injectedAmount
    );
    event LotteryNumberDrawn(
        uint256 indexed lotteryId,
        uint256 finalNumber,
        uint256 countWinningTickets
    );
    event NewOperatorAndTreasuryAndInjectorAddresses(
        address operator,
        address treasury,
        address injector
    );
    event TicketsPurchase(
        address indexed buyer,
        uint256 indexed lotteryId,
        uint256 numberTickets
    );
    event TicketsClaim(
        address indexed claimer,
        uint256 amount,
        uint256 indexed lotteryId,
        uint256 numberTickets
    );

    constructor() {
        // initialize mapping
        _poolCalculator[0] = 1;
        _poolCalculator[1] = 11;
        _poolCalculator[2] = 111;
        _poolCalculator[3] = 1111;
        _poolCalculator[4] = 11111;
        _poolCalculator[5] = 111111;
    }

    /**
     * @notice Buy tickets for the current lottery
     * @param _lotteryId: lotteryId
     * @param _ticketNumbers: array of ticket numbers between 1,000,000 and 1,999,999
     * @dev Callable by users
     */
    function buyTickets(uint256 _lotteryId, uint32[] calldata _ticketNumbers)
        external
        payable
        notProxy
        nonReentrant
    {
        require(_ticketNumbers.length != 0, "No ticket specified");
        require(
            _ticketNumbers.length <= maxNumberOfTicketsPerBuyOrClaim,
            "Too many tickets"
        );
        require(
            totalPrice(_lotteryId, _ticketNumbers.length, msg.value),
            "Insufficient funds for tickets"
        );
        require(
            _lotteries[_lotteryId].status == Status.Open,
            "Lottery is not open"
        );

        require(
            block.timestamp < _lotteries[_lotteryId].endTime,
            "Lottery is over"
        );

        // Calculate number of ETHER to this contract
        uint256 amountEtherToTransfer = _calculateTotalPriceForBulkTickets(
            _lotteries[_lotteryId].discountDivisor,
            _lotteries[_lotteryId].priceTicketInEther,
            _ticketNumbers.length
        );

        // Increment the total amount collected for the lottery round
        _lotteries[_lotteryId].amountCollectedInEther.add(
            amountEtherToTransfer
        );

        for (uint256 i = 0; i < _ticketNumbers.length; i.add(1)) {
            uint32 t_TicketNumber = _ticketNumbers[i];

            require(
                (t_TicketNumber >= 100000) && (t_TicketNumber <= 999999),
                "Outside range"
            );

            uint32 thisTicketNumber = uint32(
                reverseValueAndConvertToUint(_ticketNumbers[i])
            );

            _numberTicketsPerLotteryId[_lotteryId][1 + (thisTicketNumber % 10)]
                .add(1);
            _numberTicketsPerLotteryId[_lotteryId][
                11 + (thisTicketNumber % 100)
            ].add(1);
            _numberTicketsPerLotteryId[_lotteryId][
                111 + (thisTicketNumber % 1000)
            ].add(1);
            _numberTicketsPerLotteryId[_lotteryId][
                1111 + (thisTicketNumber % 10000)
            ].add(1);
            _numberTicketsPerLotteryId[_lotteryId][
                11111 + (thisTicketNumber % 100000)
            ].add(1);
            _numberTicketsPerLotteryId[_lotteryId][
                111111 + (thisTicketNumber % 1000000)
            ].add(1);

            _userTicketIdsPerLotteryId[msg.sender][_lotteryId].push(
                currentTicketId
            );

            _tickets[currentTicketId] = Ticket({
                number: thisTicketNumber,
                owner: msg.sender
            });

            // Increase lottery ticket number

            currentTicketId.add(1);
        }

        emit TicketsPurchase(msg.sender, _lotteryId, _ticketNumbers.length);
    }

    /**
     * @notice Claim a set of winning tickets for a lottery
     * @param _lotteryId: lottery id
     * @param _ticketIds: array of ticket ids
     * @param _pools: array of pools for the ticket ids
     * @dev Callable by users only, not contract!
     */
    function claimTickets(
        uint256 _lotteryId,
        uint256[] calldata _ticketIds,
        uint32[] calldata _pools
    ) public notProxy nonReentrant {
        require(_ticketIds.length == _pools.length, "Not same length");
        require(_ticketIds.length != 0, "Length must be >0");
        require(
            _ticketIds.length <= maxNumberOfTicketsPerBuyOrClaim,
            "Too many tickets"
        );
        require(
            _lotteries[_lotteryId].status == Status.Claimable,
            "Lottery not claimable"
        );

        // Initialize the rewardInEtherToTransfer
        uint256 rewardInEtherToTransfer;

        for (uint256 i = 0; i < _ticketIds.length; i.add(1)) {
            require(_pools[i] < 6, "Pool out of range");

            uint256 thisTicketId = _ticketIds[i];

            require(
                _lotteries[_lotteryId].firstTicketIdNextLottery > thisTicketId,
                "TicketId too high"
            );
            require(
                _lotteries[_lotteryId].firstTicketId <= thisTicketId,
                "TicketId too low"
            );
            require(
                msg.sender == _tickets[thisTicketId].owner,
                "Not the owner"
            );

            // Update the lottery ticket owner to 0x address
            _tickets[thisTicketId].owner = address(0);

            uint256 rewardForTicketId = _calculateRewardsForTicketId(
                _lotteryId,
                thisTicketId,
                _pools[i]
            );

            // Check user has claimable reward for a pool

            if (rewardForTicketId != 0) {
                // Increment the reward to transfer
                rewardInEtherToTransfer.add(rewardForTicketId);
            } else {
                // increment the reward by 0
                rewardInEtherToTransfer.add(0);
            }
        }

        // Transfer money to msg.sender
        (bool sent, ) = msg.sender.call{value: rewardInEtherToTransfer}("");
        require(sent, "Failed to send Ether");

        emit TicketsClaim(
            msg.sender,
            rewardInEtherToTransfer,
            _lotteryId,
            _ticketIds.length
        );
    }

    /**
     * @notice Close lottery
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function closeLottery(uint256 _lotteryId, uint256 _round)
        public
        onlyOperator
        nonReentrant
    {
        require(
            _lotteries[_lotteryId].status == Status.Open,
            "Lottery not open"
        );
        require(
            block.timestamp > _lotteries[_lotteryId].endTime,
            "Lottery not over"
        );
        _lotteries[_lotteryId].firstTicketIdNextLottery = currentTicketId;

        _lotteries[_lotteryId].status = Status.Closed;

        emit LotteryClosed(_lotteryId, currentTicketId);
    }

    /**
     * @notice Draw the final number, calculate reward in Ether per group, and make lottery claimable
     * @param _lotteryId: lottery id
     * @param _autoInjection: reinjects funds into next lottery (vs. withdrawing all)
     * @dev Callable by operator
     */
    function drawFinalNumberAndMakeLotteryClaimable(
        uint256 _lotteryId,
        bool _autoInjection,
        uint256 _round
    ) public onlyOperator nonReentrant {
        require(
            _lotteries[_lotteryId].status == Status.Closed,
            "Lottery not close"
        );

        uint32 finalNumber = uint32(reverseValueAndConvertToUint(number));

        uint256 numberAddressesInPreviousPool;

        uint256 amountToShareToWinners = (
            ((_lotteries[_lotteryId].amountCollectedInEther) *
                (10000 - _lotteries[_lotteryId].treasuryFee))
        ) / 10000;

        uint256 amountToWithdrawToTreasury;

        for (uint32 i = 0; i < 6; i.add(1)) {
            uint32 j = 5 - i;
            uint32 transformedWinningNumber = _poolCalculator[j] +
                (finalNumber % (uint32(10)**(j + 1)));

            _lotteries[_lotteryId].countWinnersPerPool[j] =
                _numberTicketsPerLotteryId[_lotteryId][
                    transformedWinningNumber
                ] -
                numberAddressesInPreviousPool;

            if (
                _numberTicketsPerLotteryId[_lotteryId][
                    transformedWinningNumber
                ] -
                    numberAddressesInPreviousPool !=
                0
            ) {
                if (_lotteries[_lotteryId].rewardsBreakdown[j] != 0) {
                    _lotteries[_lotteryId].etherPerPool[j] =
                        ((_lotteries[_lotteryId].rewardsBreakdown[j] *
                            amountToShareToWinners) /
                            (_numberTicketsPerLotteryId[_lotteryId][
                                transformedWinningNumber
                            ] - numberAddressesInPreviousPool)) /
                        10000;

                    numberAddressesInPreviousPool = _numberTicketsPerLotteryId[
                        _lotteryId
                    ][transformedWinningNumber];
                }
            } else {
                _lotteries[_lotteryId].etherPerPool[j] = 0;

                amountToWithdrawToTreasury +=
                    (_lotteries[_lotteryId].rewardsBreakdown[j] *
                        amountToShareToWinners) /
                    10000;
            }
        }

        _lotteries[_lotteryId].finalNumber = number;
        _lotteries[_lotteryId].status = Status.Claimable;

        if (_autoInjection) {
            pendingInjectionNextLottery = amountToWithdrawToTreasury;
            amountToWithdrawToTreasury = 0;
        }

        amountToWithdrawToTreasury.add(
            (_lotteries[_lotteryId].amountCollectedInEther -
                amountToShareToWinners)
        );

        (bool sent, ) = treasuryAddress.call{value: amountToWithdrawToTreasury}(
            ""
        );
        require(sent, "Failed to send Ether");

        emit LotteryNumberDrawn(
            currentLotteryId,
            finalNumber,
            numberAddressesInPreviousPool
        );
    }

    /**
     * @notice Inject funds
     * @param _lotteryId: lottery id
     * @dev Callable by owner or injector address
     */
    function injectFunds(uint256 _lotteryId)
        public
        payable
        onlyOwnerOrInjector
    {
        require(
            _lotteries[_lotteryId].status == Status.Open,
            "Lottery not open"
        );

        _lotteries[_lotteryId].amountCollectedInEther.add(msg.value);

        emit LotteryInjection(_lotteryId, msg.value);
    }

    /**
     * @notice Start the lottery
     * @dev Callable by operator
     * @param _endTime: endTime of the lottery
     * @param _priceTicketInEther: price of a ticket in Ether
     * @param _discountDivisor: the divisor to calculate the discount magnitude for bulks
     * @param _rewardsBreakdown: breakdown of rewards per pool (must sum to 10,000)
     * @param _treasuryFee: treasury fee (10,000 = 100%, 100 = 1%)
     */

    function startLottery(
        uint256 _endTime,
        uint256 _priceTicketInEther,
        uint256 _discountDivisor,
        uint256[6] calldata _rewardsBreakdown,
        uint256 _treasuryFee
    ) public onlyOperator {
        require(
            (currentLotteryId == 0) ||
                (_lotteries[currentLotteryId].status == Status.Claimable),
            "Not time to start lottery"
        );

        require(
            ((_endTime - block.timestamp) > MIN_LENGTH_LOTTERY) &&
                ((_endTime - block.timestamp) < MAX_LENGTH_LOTTERY),
            "Lottery length outside of range"
        );

        require(
            (_priceTicketInEther >= minPriceTicketInEther) &&
                (_priceTicketInEther <= maxPriceTicketInEther),
            "Price per ticket is out of range"
        );

        require(
            _discountDivisor >= MIN_DISCOUNT_DIVISOR,
            "Discount divisor too low"
        );
        require(_treasuryFee <= MAX_TREASURY_FEE, "Treasury fee too high");

        require(
            (_rewardsBreakdown[0] +
                _rewardsBreakdown[1] +
                _rewardsBreakdown[2] +
                _rewardsBreakdown[3] +
                _rewardsBreakdown[4] +
                _rewardsBreakdown[5]) == 10000,
            "Rewards must equal 10000"
        );

        unchecked {
            currentLotteryId.add(1);
        }

        _lotteries[currentLotteryId] = Lottery({
            status: Status.Open,
            startTime: block.timestamp,
            endTime: _endTime,
            priceTicketInEther: _priceTicketInEther,
            discountDivisor: _discountDivisor,
            rewardsBreakdown: _rewardsBreakdown,
            treasuryFee: _treasuryFee,
            etherPerPool: [
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0)
            ],
            countWinnersPerPool: [
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0)
            ],
            firstTicketId: currentTicketId,
            firstTicketIdNextLottery: currentTicketId,
            amountCollectedInEther: pendingInjectionNextLottery,
            finalNumber: 0
        });

        emit LotteryOpen(
            currentLotteryId,
            block.timestamp,
            _endTime,
            _priceTicketInEther,
            currentTicketId,
            pendingInjectionNextLottery
        );

        pendingInjectionNextLottery = 0;
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of token amount to withdraw
     * @dev Only callable by owner.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount)
        public
        onlyOwner
    {
        IERC20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /**
     * @notice Set Ether price ticket upper/lower limit
     * @dev Only callable by owner
     * @param _minPriceTicketInEther: minimum price of a ticket in Ether
     * @param _maxPriceTicketInEther: maximum price of a ticket in Ether
     */
    function setMinAndMaxTicketPriceInEther(
        uint256 _minPriceTicketInEther,
        uint256 _maxPriceTicketInEther
    ) public onlyOwner {
        require(
            _minPriceTicketInEther <= _maxPriceTicketInEther,
            "minPrice must be < maxPrice"
        );

        minPriceTicketInEther = _minPriceTicketInEther;
        maxPriceTicketInEther = _maxPriceTicketInEther;
    }

    /**
     * @notice Set operator, treasury, and injector addresses
     * @dev Only callable by owner
     * @param _operatorAddress: address of the operator
     * @param _treasuryAddress: address of the treasury
     * @param _injectorAddress: address of the injector
     */
    function setOperatorAndTreasuryAndInjectorAddresses(
        address _operatorAddress,
        address _treasuryAddress,
        address _injectorAddress
    ) public onlyOwner {
        require(_operatorAddress != address(0), "Cannot be zero address");
        require(_treasuryAddress != address(0), "Cannot be zero address");
        require(_injectorAddress != address(0), "Cannot be zero address");

        operatorAddress = _operatorAddress;
        treasuryAddress = _treasuryAddress;
        injectorAddress = _injectorAddress;

        emit NewOperatorAndTreasuryAndInjectorAddresses(
            _operatorAddress,
            _treasuryAddress,
            _injectorAddress
        );
    }

    /**
     * @notice Calculate price of a set of tickets
     * @param _discountDivisor: divisor for the discount
     * @param _priceTicket price of a ticket (in Ether)
     * @param _numberTickets number of tickets to buy
     */
    function calculateTotalPriceForBulkTickets(
        uint256 _discountDivisor,
        uint256 _priceTicket,
        uint256 _numberTickets
    ) public pure returns (uint256) {
        require(
            _discountDivisor >= MIN_DISCOUNT_DIVISOR,
            "Must be >= MIN_DISCOUNT_DIVISOR"
        );
        require(_numberTickets != 0, "Number of tickets must be > 0");

        return
            _calculateTotalPriceForBulkTickets(
                _discountDivisor,
                _priceTicket,
                _numberTickets
            );
    }

    /**
     * @notice View current lottery id
     */
    function viewCurrentLotteryId() public view returns (uint256) {
        return currentLotteryId;
    }

    /**
     * @notice View lottery information
     * @param _lotteryId: lottery id
     */
    function viewLottery(uint256 _lotteryId)
        public
        view
        returns (Lottery memory)
    {
        return _lotteries[_lotteryId];
    }

    /**
     * @notice View ticket statuses and numbers for an array of ticket ids
     * @param _ticketIds: array of _ticketId
     */
    function viewNumbersAndStatusesForTicketIds(uint256[] calldata _ticketIds)
        public
        view
        returns (uint32[] memory, bool[] memory)
    {
        uint256 length = _ticketIds.length;
        uint32[] memory ticketNumbers = new uint32[](length);
        bool[] memory ticketStatuses = new bool[](length);

        for (uint256 i = 0; i < length; i.add(1)) {
            ticketNumbers[i] = uint32(
                reverseValueAndConvertToUint(_tickets[_ticketIds[i]].number)
            );
            if (_tickets[_ticketIds[i]].owner == address(0)) {
                ticketStatuses[i] = true;
            } else {
                ticketStatuses[i] = false;
            }
        }

        return (ticketNumbers, ticketStatuses);
    }

    /**
     * @notice View rewards for a given ticket, providing a pool, and lottery id
     * @param _lotteryId: lottery id
     * @param _ticketId: ticket id
     * @param _pool: pool for the ticketId to verify the claim and calculate rewards
     */
    function viewRewardsForTicketId(
        uint256 _lotteryId,
        uint256 _ticketId,
        uint32 _pool
    ) public view returns (uint256) {
        // Check lottery is in claimable status
        if (_lotteries[_lotteryId].status != Status.Claimable) {
            return 0;
        }

        // Check ticketId is within range
        if (
            (_lotteries[_lotteryId].firstTicketIdNextLottery < _ticketId) &&
            (_lotteries[_lotteryId].firstTicketId >= _ticketId)
        ) {
            return 0;
        }

        return _calculateRewardsForTicketId(_lotteryId, _ticketId, _pool);
    }

    /**
     * @notice View maximum claimable rewards for each ticket with respect to pools
     * @param _user: user address
     * @param _lotteryId: lottery id
     * @param _cursor: starting index for ticket retrieval
     * @param _size: the number of tickets to retrieve from the _cursor
     **/
    function viewMaxRewardsForTicketId(
        address _user,
        uint256 _lotteryId,
        uint256 _cursor,
        uint256 _size
    )
        public
        view
        returns (
            uint256[] memory,
            uint32[] memory,
            uint256[] memory,
            uint32[] memory
        )
    {
        (
            uint256[] memory lotteryTicketIds,
            uint32[] memory ticketNumbers,
            ,

        ) = viewUserInfoForLotteryId(_user, _lotteryId, _cursor, _size);

        uint256[] memory maxLotteryRewardPerTicket = new uint256[](_size);
        uint32[] memory maxLotteryRewardPoolPerTicket = new uint32[](_size);
        uint256 lotteryId = _lotteryId;
        // uint32 _poolLength = 6;

        for (uint256 i = 0; i < _size; i.add(1)) {
            uint256 reward = 0;
            uint32 rewardPool = 0;

            for (uint32 _pool = 0; _pool < 6; _pool.add(1)) {
                uint256 currentReward = _calculateRewardsForTicketId(
                    lotteryId,
                    lotteryTicketIds[i],
                    uint32(_pool)
                );

                if (currentReward >= reward) {
                    reward = currentReward;
                    rewardPool = _pool;
                }

                if (reward == 0) {
                    rewardPool = 0;
                }

                // console.log(
                //     "---------------------------------------------------------------"
                // );
                // console.log("Current reward: ", currentReward);
                // console.log("pool: ", _pool);

                // console.log("reward: ", reward);
                // console.log("reward pool: ", rewardPool);
                // console.log(
                //     "---------------------------------------------------------------"
                // );
            }

            maxLotteryRewardPerTicket[i] = reward;
            maxLotteryRewardPoolPerTicket[i] = rewardPool;
        }

        return (
            lotteryTicketIds,
            ticketNumbers,
            maxLotteryRewardPerTicket,
            maxLotteryRewardPoolPerTicket
        );
    }

    /**
     * @notice Set max number of tickets
     * @dev Only callable by owner
     */
    function setMaxNumberTicketsPerBuy(uint256 _maxNumberOfTicketsPerBuy)
        public
        onlyOwner
    {
        require(_maxNumberOfTicketsPerBuy != 0, "Must be > 0");
        maxNumberOfTicketsPerBuyOrClaim = _maxNumberOfTicketsPerBuy;
    }

    /**
     * @notice View ticket ids, numbers, and statuses of user for a given lottery
     * @param _user: user address
     * @param _lotteryId: lottery id
     */
    function viewUserInfoForLotteryId(
        address _user,
        uint256 _lotteryId,
        uint256 _cursor,
        uint256 _size
    )
        public
        view
        returns (
            uint256[] memory,
            uint32[] memory,
            bool[] memory,
            uint256
        )
    {
        uint256 length = _size;
        uint256 numberTicketsBoughtAtLotteryId = _userTicketIdsPerLotteryId[
            _user
        ][_lotteryId].length;

        if (length > (numberTicketsBoughtAtLotteryId - _cursor)) {
            length = numberTicketsBoughtAtLotteryId - _cursor;
        }

        uint256[] memory lotteryTicketIds = new uint256[](length);
        uint32[] memory ticketNumbers = new uint32[](length);
        bool[] memory ticketStatuses = new bool[](length);

        for (uint256 i = 0; i < length; i.add(1)) {
            lotteryTicketIds[i] = _userTicketIdsPerLotteryId[_user][_lotteryId][
                i + _cursor
            ];
            ticketNumbers[i] = uint32(
                reverseValueAndConvertToUint(
                    _tickets[lotteryTicketIds[i]].number
                )
            );

            // True = ticket claimed
            if (_tickets[lotteryTicketIds[i]].owner == address(0)) {
                ticketStatuses[i] = true;
            } else {
                // ticket not claimed (includes the ones that cannot be claimed)
                ticketStatuses[i] = false;
            }
        }

        return (
            lotteryTicketIds,
            ticketNumbers,
            ticketStatuses,
            _cursor + length
        );
    }

    /**
     * @notice Get number of tickets a user ownes
     * @param _user: user's wallet address
     * @param _lotteryId: Lottery ID
     */
    function viewUserTicketLength(address _user, uint256 _lotteryId)
        public
        view
        returns (uint256)
    {
        uint256 numberOfTicketsBoughtAtLotteryId = _userTicketIdsPerLotteryId[
            _user
        ][_lotteryId].length;

        return numberOfTicketsBoughtAtLotteryId;
    }

    /**
     * @notice Calculate rewards for a given ticket
     * @param _lotteryId: lottery id
     * @param _ticketId: ticket id
     * @param _pool: pool for the ticketId to verify the claim and calculate rewards
     */
    function _calculateRewardsForTicketId(
        uint256 _lotteryId,
        uint256 _ticketId,
        uint32 _pool
    ) internal view returns (uint256) {
        // Retrieve the winning number combination
        uint32 winningTicketNumber = _lotteries[_lotteryId].finalNumber;
        uint256 reversedWinningTicketNumber = reverseValueAndConvertToUint(
            winningTicketNumber
        );

        // Retrieve the user number combination from the ticketId
        uint32 userNumber = _tickets[_ticketId].number;
        // uint256 reveresedUserNumber = reverseValueAndConvertToUint(userNumber);

        // Apply transformation to verify the claim provided by the user is true
        uint256 transformedWinningNumber = _poolCalculator[_pool] +
            (reversedWinningTicketNumber % (uint32(10)**(_pool + 1)));

        uint256 transformedUserNumber = _poolCalculator[_pool] +
            (userNumber % (uint32(10)**(_pool + 1)));

        // Confirm that the two transformed numbers are the same, if not throw
        if (transformedWinningNumber == transformedUserNumber) {
            return _lotteries[_lotteryId].etherPerPool[_pool];
        } else {
            return 0;
        }
    }

    /**
     * @notice Calculate final price for bulk of tickets
     * @param _discountDivisor: divisor for the discount (the smaller it is, the greater the discount is)
     * @param _priceTicket: price of a ticket
     * @param _numberTickets: number of tickets purchased
     */
    function _calculateTotalPriceForBulkTickets(
        uint256 _discountDivisor,
        uint256 _priceTicket,
        uint256 _numberTickets
    ) internal pure returns (uint256) {
        return
            (_priceTicket *
                _numberTickets *
                (_discountDivisor + 1 - _numberTickets)) / _discountDivisor;
    }

    /***
     * @notice Calculate total price of tickets
     * @param _numberTickets: number of tickets being purchased
     * @param _lotteryId: ID of lottery for which tickets are being purchased
     * @param _providedValue: msg.value gotten from buyTicket call
     */
    function totalPrice(
        uint256 _lotteryId,
        uint256 _numberTickets,
        uint256 _providedValue
    ) internal view returns (bool) {
        uint256 pricePerTicket = _lotteries[_lotteryId].priceTicketInEther;

        uint256 _totalPrice = pricePerTicket * _numberTickets;

        bool _check = _providedValue >= _totalPrice;

        return _check;
    }

    /**
     * @notice extract last 7 digits
     **/
    function st2num(string memory numString) internal pure returns (uint256) {
        bytes memory b = bytes(numString);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i.add(1)) {
            uint256 c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
        return uint256(result) % 1000000;
    }

    /**
     * @notice reverse uint value eg. 12345 -> 54321
     */
    function reverseValueAndConvertToUint(uint256 _base)
        internal
        pure
        returns (uint256)
    {
        string memory base = Strings.toString(_base);
        bytes memory _baseBytes = bytes(base);
        assert(_baseBytes.length > 0);

        string memory _tempValue = new string(_baseBytes.length);
        bytes memory _newValue = bytes(_tempValue);

        for (uint256 i = 0; i < _baseBytes.length; i.add(1)) {
            _newValue[_baseBytes.length - i - 1] = _baseBytes[i];
        }

        return st2num(string(_newValue));
    }

    /**
     * @notice withdraw contract balance to treasury
     */
    function withdraw() external payable onlyOwner {
        (bool sent, ) = treasuryAddress.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    /**
     * @notice get balance of the contract
     */
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}
