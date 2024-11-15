// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
 

contract RaffleTest is Test, CodeConstants {
    Raffle public raffle;
    //Events

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    HelperConfig public helperConfig;
    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitializdInOpenState() external view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertWhenYouDoNotPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughEtherSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEmitEvent() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upKeepNeeded,) = raffle.checkUpkeep("");
        assert(!upKeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfRaffleIsntOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        (bool upKeepNeeded,) = raffle.checkUpkeep("");
        assert(!upKeepNeeded);
    }

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
    }

    function testPerformUpKeepRevertIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 newPlayers = 0;
        Raffle.RaffleState rstate = raffle.getRaffleState();
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        newPlayers = 1;
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__upKeepNotNeeded.selector, currentBalance, newPlayers, rstate)
        );
        raffle.performUpkeep("");
    }

    function testPerformUpKeepUpdateRaffle() public raffleEntered {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork () {
        if(block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testfulfilRandomwordCanOnlyBeCallAfterPerformUpkeep(uint256 randomRequestId) public raffleEntered skipFork {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(0, address(raffle));
    }

    function testFulfilRandomWordsPickAWinnerAndSendMoney() public raffleEntered skipFork {
       uint256 additionalEntrance = 3;
    uint256 startingIndex = 1;
    address expectedWinner = address(1); // Assuming the expected winner is the address at index 1.

    // Loop to add additional players
    for (uint256 i = startingIndex; i < startingIndex + additionalEntrance; i++) {
        address newPlayer = address(uint160(i));
        hoax(newPlayer, 1 ether); // Using hoax to simulate a player with 1 ether
        raffle.enterRaffle{value: entranceFee}();
    }

    uint256 startingTimestamp = raffle.getLastTimeStamp();
    uint256 winnerStartingBalance = expectedWinner.balance;

    // Record logs before performing upkeep
    vm.recordLogs();
    raffle.performUpkeep(""); // Trigger the upkeep to start the randomization process

    // Get all recorded logs
    Vm.Log[] memory entries = vm.getRecordedLogs();
    
    // Assuming the requestId is in topic[1] of the second log entry (entries[1])
    bytes32 requestId = entries[1].topics[1];
    
    // Fulfill random words with the requestId and contract address
    VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

    // Check the recent winner and contract state
    address recentWinner = raffle.getRecentWinner();
    Raffle.RaffleState raffleState = raffle.getRaffleState();
    uint256 winnerBalance = recentWinner.balance;
    uint256 endingTimeStamp = raffle.getLastTimeStamp();
    
    uint256 price = entranceFee * (additionalEntrance + 1);
        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + price);
        assert(endingTimeStamp > startingTimestamp);
    }
}
