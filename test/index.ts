import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import moment from "moment";
// eslint-disable-next-line node/no-missing-import
// import transformer from "./helper";

let CoinsinoContract: any, currentLotteryId: number;

// price per ticket
const pricePerTicket = "15";

/* ---------------------------------------------------------------start of helper functions------------------------------------------------------------------ */

function convertInput(date: string) {
  const splitDate: any = date.split(" ");
  const value: number = parseInt(splitDate[0]);
  const interval: any = splitDate[1];

  const epoch = moment(new Date()).add(value, interval).toDate();
  const _epoch = moment(epoch).unix();

  return _epoch;
}

async function generatePoolArray(length: number, poolId: number) {
  const pool = Array.from({ length }, (v, k) => poolId);
  return pool;
}

async function generateRandom() {
  const rand = Math.floor(Math.random() * 899999 + 100000);

  return rand;
}

async function generateTicketNumbers(numberOfTickets: number) {
  const numbers: Array<number> = [];

  for (let i = 0; i < numberOfTickets; i++) {
    const ticket = await generateRandom();
    const ticketString = String(ticket);
    const lastValue = Number(ticketString[ticketString.length - 1]);

    if (lastValue === 0) {
      const padding = Math.floor(Math.random() * 8 + 1);
      const final = ticket + padding;
      numbers.push(final);
    } else {
      numbers.push(ticket);
    }
  }
  return numbers;
}

async function viewLotteryStatus(currentLotteryId: number) {
  return await CoinsinoContract.viewLottery(currentLotteryId);
}

/* -------------------------------------------------------------------End of helper functions------------------------------------------------------------------- */

describe("first", function () {
  it("test", async () => {
    const oneMinute = await convertInput("2 minutes");
    console.log(oneMinute);
  });
});

describe("Coinsino contract", function () {
  it("Should deploy and set operator", async function () {
    // Get Coinsino contract and deploy
    const coinsino = await ethers.getContractFactory("Coinsino");
    CoinsinoContract = await coinsino.deploy();

    // simulate simple deployment and listing
    await CoinsinoContract.deployed();

    const [operator, treasury, injector] = await ethers.getSigners();

    // set operator, treasury and injector
    await CoinsinoContract.setOperatorAndTreasuryAndInjectorAddresses(
      operator.address,
      treasury.address,
      injector.address
    );
  });

  it("Should start a lottery and get lottery details", async function () {
    // get address
    const [operator] = await ethers.getSigners();

    // time frame
    const oneMinute = await convertInput("1 minutes");

    // start a lottery
    const startLottery = await CoinsinoContract.connect(operator).startLottery(
      oneMinute,
      ethers.utils.parseUnits(pricePerTicket, "ether"),
      300,
      [500, 960, 1430, 1910, 2390, 2810],
      1000
    );

    // start lottery
    await startLottery;

    // get current lottery id
    currentLotteryId = await Number(
      await CoinsinoContract.viewCurrentLotteryId()
    );

    // get lottery details
    const _getLottery = await viewLotteryStatus(currentLotteryId);

    /* expect the lottery status to be 1 = Open;
      where Status {
        Pending = 0,
        Open = 1,
        Closed = 2,
        Claimable = 3
    }
    */
    expect(_getLottery.status).to.be.equal(1);
  });

  it("Should inject funds into a lottery", async function () {
    // get address
    const [, , injector] = await ethers.getSigners();

    // amount to inject
    const amount = ethers.utils.parseUnits("3000", "ether");

    // approve amount for injection
    // await Ether.connect(injector).approve(CoinsinoContract.address, {value: });

    // inject funds into lottery
    await CoinsinoContract.connect(injector).injectFunds(currentLotteryId, {
      value: amount,
    });
  });

  it("Should allow users to buy tickets", async function () {
    // get address
    const [, , , user1, user2, user3] = await ethers.getSigners();

    // generate ticket
    const numberOfTickets = 20;
    const tickets = await generateTicketNumbers(numberOfTickets);

    // console.log("Test tickets: ", tickets);

    // calculate amount of tokens to approve for transaction
    const _costOfTickets = ethers.utils.parseUnits(
      String(Number(pricePerTicket) * numberOfTickets),
      "ether"
    );
    const costOfTickets = BigNumber.from(String(_costOfTickets));

    // buy a ticket and wait for completion
    const buyTicket = await CoinsinoContract.connect(user1).buyTickets(
      currentLotteryId,
      tickets,
      { value: costOfTickets }
    );

    await buyTicket.wait();

    // ----------------------------- Buy with user2 account ---------------------------- //
    const numberOfTickets2 = 30;
    const tickets2 = await generateTicketNumbers(numberOfTickets2);

    // calculate amount of tokens to approve for transaction
    const _costOfTickets2 = ethers.utils.parseUnits(
      String(Number(pricePerTicket) * numberOfTickets2),
      "ether"
    );
    const costOfTickets2 = BigNumber.from(String(_costOfTickets2));

    // buy a ticket and wait for completion
    const buyTicket2 = await CoinsinoContract.connect(user2).buyTickets(
      currentLotteryId,
      tickets2,
      { value: costOfTickets2 }
    );

    await buyTicket2.wait();

    // ---------------------------- Buy with user3 account  ---------------------------//
    const numberOfTickets3 = 6;
    // const _tickets3 = await generateTicketNumbers(numberOfTickets3);
    const tickets3 = [402532, 402582, 400012, 370534, 370403, 402123];

    // calculate amount of tokens to approve for transaction
    const _costOfTickets3 = ethers.utils.parseUnits(
      String(Number(pricePerTicket) * numberOfTickets3),
      "ether"
    );
    const costOfTickets3 = BigNumber.from(String(_costOfTickets3));

    // buy a ticket and wait for completion
    const buyTicket3 = await CoinsinoContract.connect(user3).buyTickets(
      currentLotteryId,
      tickets3,
      { value: costOfTickets3 }
    );

    await buyTicket3.wait();

    // ---------------------------- Buy with user3 account again  ---------------------------//
    const numberOfTickets32 = 25;
    const _tickets32 = await generateTicketNumbers(numberOfTickets32);
    // const tickets3 = [402532, 402582, 400012, 370534, 370403, 402123];

    // calculate amount of tokens to approve for transaction
    const _costOfTickets32 = ethers.utils.parseUnits(
      String(Number(pricePerTicket) * numberOfTickets32),
      "ether"
    );
    const costOfTickets32 = BigNumber.from(String(_costOfTickets32));

    // buy a ticket and wait for completion
    const buyTicket32 = await CoinsinoContract.connect(user3).buyTickets(
      currentLotteryId,
      _tickets32,
      { value: costOfTickets32 }
    );

    await buyTicket32.wait();

    // ---------------------------------- end of buys ---------------------------------- //

    const contractBalance = Number(
      ethers.utils.formatEther(await CoinsinoContract.getBalance())
    );

    const total =
      3000 +
      (Number(_costOfTickets) +
        Number(_costOfTickets2) +
        Number(_costOfTickets3) +
        Number(_costOfTickets32)) /
        10 ** 18;

    expect(total).to.be.equal(contractBalance);
  });

  it("User should have atleast 10 tickets", async function () {
    // get address
    const [, , , user1] = await ethers.getSigners();

    // get user info for lottery
    const userInfo = await CoinsinoContract.viewUserInfoForLotteryId(
      user1.address,
      currentLotteryId,
      0,
      20
    );

    /* userInfo[1] ==> ticket numbers.
      ticket array should have atleat 1 ticket ([tickets] > 0)
    */
    expect(userInfo[1].length).to.be.greaterThan(10);
  });

  it("Should fail to close lottery", async function () {
    // get address
    const [operator] = await ethers.getSigners();

    // initiate close lottery and expect "Lottery not over" reversion error
    await expect(
      CoinsinoContract.connect(operator).closeLottery(
        currentLotteryId,
        data.round
      )
    ).to.be.revertedWith("Lottery not over");
  });

  it("Should wait for 2.5 minutes and successfully close the lottery", async function () {
    // set 2.5 minutes timeout
    this.timeout(80000);
    await new Promise((resolve) => setTimeout(resolve, 70000));

    // get address
    const [operator] = await ethers.getSigners();

    await CoinsinoContract.connect(operator).closeLottery(
      currentLotteryId,
      data.round
    );
    // get lottery details
    const _getLottery = await viewLotteryStatus(currentLotteryId);

    /* expect the lottery status to be 1 = Open;
        where Status {
          Pending = 0,
          Open = 1,
          Closed = 2,
          Claimable = 3
      }
      */
    // const check = await CoinsinoContract.viewLottery(1);

    // console.log("Here: ", check);

    // lottery status should be Closed (2)
    expect(_getLottery.status).to.be.equal(2);
  });

  it("Should draw winning number and make lottery claimable", async function () {
    // get address
    const [operator] = await ethers.getSigners();

    // Draw winning number and make lottery claimable
    const tx = await CoinsinoContract.connect(
      operator
    ).drawFinalNumberAndMakeLotteryClaimable(
      currentLotteryId,
      false,
      data.round
    );

    await tx.wait;

    // get lottery details
    const _getLottery = await viewLotteryStatus(currentLotteryId);

    /* expect the lottery status to be 1 = Open;
      where Status {
        Pending = 0,
        Open = 1,
        Closed = 2,
        Claimable = 3
    }
    */

    // lottery status should be Claimable (3)
    expect(_getLottery.status).to.be.equal(3);
  });

  it("Should get status for ticketIds", async function () {
    // get address
    const [, , , user1] = await ethers.getSigners();

    // get user info for lottery
    const userInfo = await CoinsinoContract.viewUserInfoForLotteryId(
      user1.address,
      currentLotteryId,
      0,
      20
    );

    await CoinsinoContract.viewNumbersAndStatusesForTicketIds(userInfo[0]);

    // console.log(status);
  });

  it("Should reward user1 if they win anything for pool 0", async function () {
    // get address
    const [, , , user1] = await ethers.getSigners();

    // const check = await CoinsinoContract.viewLottery(currentLotteryId);
    // console.log(check);

    // get user info for lottery
    const userInfo = await CoinsinoContract.viewUserInfoForLotteryId(
      user1.address,
      currentLotteryId,
      0,
      20
    );

    // console.log(userInfo);

    // const checkStatus =
    //   await CoinsinoContract.viewNumbersAndStatusesForTicketIds([
    //     0, 1, 2, 3, 4, 5,
    //   ]);
    // console.log("-----------------------------------------------");
    // console.log("Statuses: ", checkStatus);

    // get balance before claimTickets is initiated
    const user1balanceBefore = Number(
      ethers.utils.formatEther(await user1.getBalance())
    );

    const pools = await generatePoolArray(20, 0);

    const ticketIds = [];

    for (let i = 0; i < userInfo[0].length; i++) {
      const ticketId = Number(userInfo[0][i]);
      ticketIds.push(ticketId);
    }

    const claimTickets = await CoinsinoContract.connect(user1).claimTickets(
      currentLotteryId,
      ticketIds,
      pools
    );
    await claimTickets.wait();
    // const events = await claimTickets.wait();
    // const event = events.events?.filter((x: { event: string }) => {
    //   return x.event === "TicketsClaim";
    // });

    // get balance after claimTickets has completed
    const user1balanceAfter = Number(
      ethers.utils.formatEther(await user1.getBalance())
    );

    // console.log(event[0].args);
    expect(user1balanceAfter).to.be.above(user1balanceBefore);
  });

  it("Should reward user2 if they win anything for pool 0", async function () {
    // get address
    const [, , , , user2] = await ethers.getSigners();

    // get user2 info for lottery
    const userInfo2 = await CoinsinoContract.viewUserInfoForLotteryId(
      user2.address,
      currentLotteryId,
      0,
      30
    );

    const ticketIds2 = userInfo2[0];
    const pools2 = await generatePoolArray(30, 0);
    // console.log(ticketIds);

    // get balance before claimTickets is initiated
    const user2balanceBefore = Number(
      ethers.utils.formatEther(await user2.getBalance())
    );

    const tx = await CoinsinoContract.connect(user2).claimTickets(
      currentLotteryId,
      ticketIds2,
      pools2
    );

    await tx.wait();

    // get balance after claimTickets has completed
    const user2balanceAfter = Number(
      ethers.utils.formatEther(await user2.getBalance())
    );

    expect(user2balanceAfter).to.be.above(user2balanceBefore);
  });

  it("Should reward user3 if they win anything for pool 0", async function () {
    // get address
    const [, , , , , user3] = await ethers.getSigners();

    // get user2 info for lottery
    const userInfo3 = await CoinsinoContract.viewUserInfoForLotteryId(
      user3.address,
      currentLotteryId,
      0,
      31
    );

    const ticketIds3 = userInfo3[0];
    const pools3 = await generatePoolArray(31, 5);

    // get balance before claimTickets is initiated
    const user3balanceBefore = Number(
      ethers.utils.formatEther(await user3.getBalance())
    );

    const tx = await CoinsinoContract.connect(user3).claimTickets(
      currentLotteryId,
      ticketIds3,
      pools3
    );

    await tx.wait();

    // get balance after claimTickets has completed
    const user3balanceAfter = Number(
      ethers.utils.formatEther(await user3.getBalance())
    );

    // console.log({ user3balanceBefore, user3balanceAfter });

    expect(user3balanceAfter).to.be.above(user3balanceBefore);
  });

  it("Should get balance of the contract", async function () {
    const balanceContract = Number(
      ethers.utils.formatEther(await CoinsinoContract.getBalance())
    );

    console.log({ "Contract balance after all payouts": balanceContract });
  });

  it("Should get balance of treasury", async function () {
    const [, treasury] = await ethers.getSigners();
    const balanceTreasury = Number(
      ethers.utils.formatEther(await treasury.getBalance())
    );

    console.log(balanceTreasury);
  });

  // <------------------------------------------------------Testing viewRewards for ticketIds ---------------------------------------------------->
  it("Should return arrays for max rewards per ticket", async function () {
    // get address
    const [, , , , , user3] = await ethers.getSigners();

    // get user info for lottery
    const userInfo = await CoinsinoContract.viewMaxRewardsForTicketId(
      user3.address,
      currentLotteryId,
      0,
      31
    );

    console.log(userInfo);
  });

  it("User3 should have 31 tickets", async function () {
    // get address
    const [, , , , , user3] = await ethers.getSigners();

    // get number of tickets
    const userInfo = await CoinsinoContract.viewUserTicketLength(
      user3.address,
      currentLotteryId
    );

    expect(Number(userInfo)).to.be.equal(31);
  });

  it("Should fail to fetch max rewards for user 4", async function () {
    // get user 4 address
    const [, , , , , , user4] = await ethers.getSigners();

    // get user info for lottery
    const userInfo = await CoinsinoContract.viewMaxRewardsForTicketId(
      user4.address,
      currentLotteryId,
      0,
      0
    );

    console.log(userInfo);

    await expect(
      CoinsinoContract.viewMaxRewardsForTicketId(
        user4.address,
        currentLotteryId
      )
    ).to.be.revertedWith("User has no tickets for this lottery");
  });
});
