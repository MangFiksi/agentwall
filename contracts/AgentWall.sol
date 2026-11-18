// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface for the Agent ID NFT contract (SPACE ID Agent ID).
/// @dev An address "holds an Agent ID" iff balanceOf(address) > 0.
interface IAgentID {
    function balanceOf(address account) external view returns (uint256);
}

/// @title AgentWall — an on-chain guestbook & daily check-in wall for Agent ID holders
/// @notice Only wallets that hold an Agent ID (an on-chain `name.ai` identity issued
///         for Agentic Wallets) can post messages or check in. Everyone can read.
///
/// @dev DESIGN / SAFETY NOTES (for reviewers and the hackathon panel):
/// - The contract NEVER holds, receives, or transfers user assets. Every function
///   is non-payable, and there is no receive()/fallback(), so plain BNB transfers
///   to this contract revert. There is nothing to withdraw and nothing to steal.
/// - No approvals are requested from users, ever. Posting and checking in are
///   ordinary, user-confirmed transactions signed in the user's own wallet.
/// - Agent ID is used only as a read-only membership check (balanceOf > 0) on the
///   official Agent ID contract. The contract cannot look up, move, or affect
///   anyone's Agent ID or wallet.
///
/// DEPLOYMENT (via the canonical CREATE2 factory):
/// - This contract is deployed through the canonical deterministic deployment
///   proxy (the "CREATE2 factory", 0x4e59b44847b379578588920cA78FbF26c0B4956C,
///   present on BNB Chain mainnet). Reason: the owner's Agentic Wallet tooling
///   sends contract calls to an existing `to` address and cannot send a bare
///   contract-creation transaction, so deployment is a plain call to the
///   factory carrying (salt ‖ init code).
/// - Under a factory deploy, `msg.sender` inside the constructor is the
///   FACTORY, not the deploying wallet. The constructor therefore takes an
///   explicit `initialOwner_` argument and assigns ownership to it, instead of
///   to msg.sender. For the production deployment, initialOwner_ is the
///   owner's Agentic Wallet address; the factory itself never holds any
///   privilege over this contract (it is not the owner and cannot call any
///   owner function).
///
/// OWNER PERMISSIONS (complete list — nothing else is privileged):
/// - setAgentID(address): point the membership check at a different Agent ID
///   contract address (e.g. if Binance/SPACE ID migrates the contract).
/// - pause() / unpause(): stop or resume postMessage() and checkIn().
///   Pausing cannot delete posts, change streaks, or touch user assets (there
///   are none in the contract).
/// - transferOwnership(address): hand the owner role to another address.
/// The owner CANNOT post on behalf of others, edit or delete messages, alter
/// check-in streaks, or move funds.
contract AgentWall {
    // ------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------

    /// @notice Maximum message length, in bytes (UTF-8).
    uint256 public constant MAX_TEXT_BYTES = 280;

    /// @notice Minimum seconds between two posts from the same address.
    uint256 public constant POST_COOLDOWN = 1 hours;

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------

    /// @notice The Agent ID contract used for the membership check.
    IAgentID public agentID;

    /// @notice The privileged address (see "OWNER PERMISSIONS" above).
    address public owner;

    /// @notice When true, postMessage() and checkIn() revert.
    bool public paused;

    struct Post {
        address author;
        string text;
        uint256 timestamp;
    }

    Post[] private _posts;

    /// @notice Last time each address posted (for the cooldown).
    mapping(address => uint256) public lastPostAt;

    /// @notice Current consecutive-day check-in streak per address.
    mapping(address => uint256) public checkInStreak;

    /// @notice Lifetime number of check-ins per address.
    mapping(address => uint256) public totalCheckIns;

    /// @notice Day index (block.timestamp / 1 days) of the last check-in,
    ///         stored as dayIndex + 1 so that 0 means "never checked in".
    mapping(address => uint256) private _lastCheckInDayPlusOne;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    event MessagePosted(address indexed author, uint256 indexed postId, string text, uint256 timestamp);
    event CheckedIn(address indexed user, uint256 streak, uint256 totalCheckIns, uint256 timestamp);
    event AgentIDUpdated(address indexed previousAgentID, address indexed newAgentID);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------

    error NotHolder(address account);
    error EmptyText();
    error TextTooLong(uint256 length, uint256 maxLength);
    error CooldownActive(uint256 availableAt);
    error AlreadyCheckedInToday();
    error ContractPaused();
    error NotOwner(address caller);
    error ZeroAddress();

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier onlyHolder() {
        if (!isHolder(msg.sender)) revert NotHolder(msg.sender);
        _;
    }

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    /// @param agentID_ Address of the Agent ID contract on BNB Chain
    ///        (mainnet: 0x60b9262456de011f7d15a54cdd8c48baaa8b022f).
    /// @param initialOwner_ Address that becomes `owner`. Passed explicitly
    ///        rather than read from msg.sender, because deployment goes through
    ///        the CREATE2 factory (see "DEPLOYMENT" in the contract header):
    ///        inside this constructor, msg.sender is the factory contract, not
    ///        the deploying wallet.
    constructor(address agentID_, address initialOwner_) {
        if (agentID_ == address(0)) revert ZeroAddress();
        if (initialOwner_ == address(0)) revert ZeroAddress();
        agentID = IAgentID(agentID_);
        owner = initialOwner_;
        emit AgentIDUpdated(address(0), agentID_);
        emit OwnershipTransferred(address(0), initialOwner_);
    }

    // ------------------------------------------------------------------
    // Read functions (free, callable by anyone)
    // ------------------------------------------------------------------

    /// @notice True iff `account` currently holds at least one Agent ID.
    function isHolder(address account) public view returns (bool) {
        return agentID.balanceOf(account) > 0;
    }

    /// @notice Total number of messages ever posted to the wall.
    function totalPosts() external view returns (uint256) {
        return _posts.length;
    }

    /// @notice Fetch a single post by its index (0 = oldest).
    function getPost(uint256 index) external view returns (address author, string memory text, uint256 timestamp) {
        Post storage p = _posts[index];
        return (p.author, p.text, p.timestamp);
    }

    /// @notice Fetch a page of posts, oldest first.
    /// @param offset Index of the first post to return.
    /// @param limit  Maximum number of posts to return.
    function getPosts(uint256 offset, uint256 limit) external view returns (Post[] memory page) {
        uint256 total = _posts.length;
        if (offset >= total || limit == 0) {
            return new Post[](0);
        }
        uint256 count = total - offset;
        if (count > limit) count = limit;
        page = new Post[](count);
        for (uint256 i = 0; i < count; i++) {
            page[i] = _posts[offset + i];
        }
        return page;
    }

    /// @notice Current check-in streak and lifetime check-ins for an address.
    function getCheckInStats(address account) external view returns (uint256 streak, uint256 total) {
        return (checkInStreak[account], totalCheckIns[account]);
    }

    /// @notice Whether `account` has already checked in on the current UTC day.
    function hasCheckedInToday(address account) external view returns (bool) {
        return _lastCheckInDayPlusOne[account] == (block.timestamp / 1 days) + 1;
    }

    // ------------------------------------------------------------------
    // Write functions (Agent ID holders only, always user-confirmed)
    // ------------------------------------------------------------------

    /// @notice Post a short message to the wall.
    /// @dev Requirements: caller holds an Agent ID; contract not paused;
    ///      1..280 bytes of text; at most one post per POST_COOLDOWN (1 hour).
    /// @param text The message (max 280 bytes).
    /// @return postId The index of the new post.
    function postMessage(string calldata text) external whenNotPaused onlyHolder returns (uint256 postId) {
        uint256 len = bytes(text).length;
        if (len == 0) revert EmptyText();
        if (len > MAX_TEXT_BYTES) revert TextTooLong(len, MAX_TEXT_BYTES);

        uint256 availableAt = lastPostAt[msg.sender] + POST_COOLDOWN;
        if (lastPostAt[msg.sender] != 0 && block.timestamp < availableAt) {
            revert CooldownActive(availableAt);
        }
        lastPostAt[msg.sender] = block.timestamp;

        postId = _posts.length;
        _posts.push(Post({author: msg.sender, text: text, timestamp: block.timestamp}));
        emit MessagePosted(msg.sender, postId, text, block.timestamp);
    }

    /// @notice Check in for today. Consecutive UTC days build a streak;
    ///         missing a day resets the streak to 1 on the next check-in.
    /// @return streak The caller's streak after this check-in.
    function checkIn() external whenNotPaused onlyHolder returns (uint256 streak) {
        uint256 today = block.timestamp / 1 days;
        uint256 lastPlusOne = _lastCheckInDayPlusOne[msg.sender];

        if (lastPlusOne == today + 1) revert AlreadyCheckedInToday();

        if (lastPlusOne == today) {
            // Last check-in was yesterday: streak continues.
            streak = checkInStreak[msg.sender] + 1;
        } else {
            // First ever check-in, or a day was missed: streak restarts.
            streak = 1;
        }

        checkInStreak[msg.sender] = streak;
        totalCheckIns[msg.sender] += 1;
        _lastCheckInDayPlusOne[msg.sender] = today + 1;

        emit CheckedIn(msg.sender, streak, totalCheckIns[msg.sender], block.timestamp);
    }

    // ------------------------------------------------------------------
    // Owner functions (complete list — see contract header)
    // ------------------------------------------------------------------

    /// @notice Point the membership check at a new Agent ID contract.
    function setAgentID(address newAgentID) external onlyOwner {
        if (newAgentID == address(0)) revert ZeroAddress();
        address previous = address(agentID);
        agentID = IAgentID(newAgentID);
        emit AgentIDUpdated(previous, newAgentID);
    }

    /// @notice Pause posting and check-ins (reads keep working).
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Resume posting and check-ins.
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Transfer the owner role to another address.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address previous = owner;
        owner = newOwner;
        emit OwnershipTransferred(previous, newOwner);
    }
}
