// SPDX-License-Identifier: MIT
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

pragma solidity ^0.8.19;

// ** Imports **
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
    * @title Raffle house contract
    * @dev Raffle contract is a smart contract for managing a raffle impliments Chainlink VRFv2.   
    * @notice The contract allows the owner to set the raffle prize, the ticket price, the number of tickets, and the duration of the raffle.
    * @notice The contract allows participants to buy tickets and the owner to draw a winner.
    * @dev The contract uses Chainlink VRFv2 to generate a random number to select the winner.
    * @author Nigel Spooner


 */

contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    // bool lottertState = open, closed, calculating
    // ** Type Declarations */

    enum RaffleState {
        OPEN, // Raffle is open state 0
        // Closed,
        CALCULATING // Raffle is calculating state 2
    }

    // ** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    // ** State immutable Variables */
    uint256 private immutable i_entranceFee; // Cost of a ticket
    uint256 private immutable i_interval; // Duration of the raffle in seconds
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator; // Chainlink VRF Coordinator
    bytes32 private immutable i_gasLane; // Chainlink VRF gas lane
    uint64 private immutable i_subscriptionId; // Chainlink VRF subscription ID
    uint32 private immutable i_callbackGaslimit; // Chainlink VRF callback gas limit

    //** State s Variables Storage */
    address payable[] private s_players; // Array of players
    uint256 private s_lastTimeStamp; // Last time the raffle was called (timestamp)
    address private s_resentWinner; // Last winner of the raffle
    RaffleState private s_raffleState; // State of the raffle
    // uint256 private s_raffleDuration;
    // uint256 private i_rafflePrize;

    /** Events */
    event EnterRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGaslimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGaslimit = callbackGaslimit;
        s_raffleState = RaffleState.OPEN; // Set the initial state of the raffle

        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        //require(msg.value >= i_entranceFee, "Not enough ETH to enter the raffle");
        if (msg.value < i_entranceFee) {
            // Check if the user has sent enough ETH to enter the raffle
            revert Raffle__NotEnoughEthSent();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen(); // Raffle is not open
        }

        s_players.push(payable(msg.sender));
        // 1. Makes magrations easier
        // 2. Makes frontend "indexing" easier
        emit EnterRaffle(msg.sender); // Emit an event
    }

    /**
     * @dev This is the unction that chainlink Automation nodes call
     * to see if it's time to perform an upkeep
     * The following should be true for this to return true:
     * 1. The time interval has passed between the Raffle runs
     * 2. The Raffle is in the open state
     * 3. The contract has ETH (aka, Players)
     * 4. (Implicit) The subscription is funded with LINK
     */

    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp >= i_interval);
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    // 1. Pick a random number
    // 2. Use that number to pick a winner
    // 3. Be automatically called after the raffle duration

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep(""); // Check if upkeep is needed
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            ); // error message
        }
        // Chainlink VRF function
        block.timestamp - s_lastTimeStamp > i_interval;
        if (block.timestamp - s_lastTimeStamp < i_interval) {
            revert();
        }
        s_raffleState = RaffleState.CALCULATING;

        i_vrfCoordinator.requestRandomWords( // Chainlink VRF function
                i_gasLane, //keyHash = gas lane
                i_subscriptionId,
                REQUEST_CONFIRMATIONS,
                i_callbackGaslimit,
                NUM_WORDS
            );
    }

    // CFI - CHECKS, EFFECTS, INTERACTIONS

    function fulfillRandomWords(
        // Chainlink VRF callback function
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        // Checks,
        // Effects,
        // Interactions

        uint256 indexOfWinner = randomWords[0] % s_players.length; // Pick a winner
        address payable winner = s_players[indexOfWinner]; // Use the random number to pick a winner
        s_resentWinner = winner; // Store the winner
        s_raffleState = RaffleState.OPEN; // Set the state of the raffle to open

        s_players = new address payable[](0); // Reset the players array
        s_lastTimeStamp = block.timestamp; // Reset the last time the raffle was called

        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed(); // Transfer failed
        }
        emit PickedWinner(winner); // Emit an event
    }

    // ** Getter functions **

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 index0Player) external view returns (address) {
        return s_players[index0Player];
    }
}
