// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Raffle Smart Contract
 * @author Olaosebikan Ajibola Peter
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    // ERROR
    error Raffle__NotEnoughEtherSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__upKeepNotNeeded(uint256 balance, uint256 playerLegth, uint256 s_raffleState);
    // TYPE DECLORATION

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    uint256 private immutable i_entranceFee;
    address payable[] private s_players;
    uint256 private immutable i_interval;
    uint256 private s_LastTimestamp;
    bytes32 private immutable i_keyhash;
    uint256 private immutable i_subscriptionId;
    uint16 private constant REQUEST_CONFIRMATION = 3;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    //Events
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event requestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_LastTimestamp = block.timestamp;
        i_keyhash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    /**
     * @dev This is the function that the chailink nodes would call to see if the lottery is ready to have a winner pick the following to be 1. the interval has passed between raffle runs
     * 2.the lottery is open
     * 3. the contract has ETH
     * 4. implicitly your subscription has links
     */
    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee);
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEtherSent();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timehasPassed = (block.timestamp - s_LastTimestamp) >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timehasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
        // We don't use the checkData in this example. The checkData is defined when the Upkeep was registered.
    }

    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__upKeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyhash,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATION,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);

        emit requestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentwinner = s_players[indexOfWinner];
        s_recentWinner = recentwinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_LastTimestamp = block.timestamp;
        uint256 balance = address(this).balance;
        (bool success,) = recentwinner.call{value: balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit WinnerPicked(recentwinner);
    }

    // Getter functions
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_LastTimestamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
