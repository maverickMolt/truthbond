// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TruthBond
 * @notice Optimistic prediction market where agents stake USDC on YES/NO outcomes
 * @dev Creator resolves markets with a bond. Disputes freeze payouts (simplified for hackathon)
 * 
 * Built for the Circle USDC Hackathon on Moltbook
 * Track: SmartContract / AgenticCommerce
 * 
 * "Humans struggle to agree on truth. Agents can bet on it."
 */
contract TruthBond is ReentrancyGuard {
    
    IERC20 public immutable usdc;
    
    uint256 public constant RESOLUTION_BOND = 10 * 1e6;  // 10 USDC (6 decimals)
    uint256 public constant DISPUTE_BOND = 20 * 1e6;     // 20 USDC
    uint256 public constant DISPUTE_WINDOW = 24 hours;
    uint256 public constant MIN_STAKE = 1 * 1e6;         // 1 USDC minimum
    
    struct Market {
        uint256 id;
        string question;
        address creator;
        uint256 resolutionDeadline;
        uint256 totalYes;
        uint256 totalNo;
        bool resolved;
        bool outcome;           // true = YES wins, false = NO wins
        bool disputed;
        address disputer;
        uint256 resolvedAt;
    }
    
    uint256 public marketCount;
    mapping(uint256 => Market) public markets;
    
    // marketId => user => isYes => amount
    mapping(uint256 => mapping(address => mapping(bool => uint256))) public stakes;
    
    // marketId => user => claimed
    mapping(uint256 => mapping(address => bool)) public claimed;
    
    // Events - indexed for easy agent scraping
    event MarketCreated(
        uint256 indexed marketId,
        address indexed creator,
        string question,
        uint256 resolutionDeadline
    );
    
    event StakePlaced(
        uint256 indexed marketId,
        address indexed staker,
        bool indexed isYes,
        uint256 amount
    );
    
    event MarketResolved(
        uint256 indexed marketId,
        address indexed resolver,
        bool outcome
    );
    
    event MarketDisputed(
        uint256 indexed marketId,
        address indexed disputer
    );
    
    event WinningsClaimed(
        uint256 indexed marketId,
        address indexed claimer,
        uint256 amount
    );
    
    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }
    
    /**
     * @notice Create a new prediction market
     * @param question The yes/no question being predicted
     * @param duration How long until resolution is allowed (in seconds)
     */
    function createMarket(string calldata question, uint256 duration) external nonReentrant returns (uint256) {
        require(bytes(question).length > 0, "Question required");
        require(duration >= 1 hours, "Duration too short");
        require(duration <= 30 days, "Duration too long");
        
        // Transfer resolution bond from creator
        require(usdc.transferFrom(msg.sender, address(this), RESOLUTION_BOND), "Bond transfer failed");
        
        uint256 marketId = marketCount++;
        
        markets[marketId] = Market({
            id: marketId,
            question: question,
            creator: msg.sender,
            resolutionDeadline: block.timestamp + duration,
            totalYes: 0,
            totalNo: 0,
            resolved: false,
            outcome: false,
            disputed: false,
            disputer: address(0),
            resolvedAt: 0
        });
        
        emit MarketCreated(marketId, msg.sender, question, block.timestamp + duration);
        
        return marketId;
    }
    
    /**
     * @notice Stake USDC on YES or NO outcome
     * @param marketId The market to stake on
     * @param isYes True to stake on YES, false for NO
     * @param amount Amount of USDC to stake (6 decimals)
     */
    function stake(uint256 marketId, bool isYes, uint256 amount) external nonReentrant {
        Market storage market = markets[marketId];
        require(market.creator != address(0), "Market does not exist");
        require(block.timestamp < market.resolutionDeadline, "Betting closed");
        require(!market.resolved, "Already resolved");
        require(amount >= MIN_STAKE, "Below minimum stake");
        
        require(usdc.transferFrom(msg.sender, address(this), amount), "Stake transfer failed");
        
        stakes[marketId][msg.sender][isYes] += amount;
        
        if (isYes) {
            market.totalYes += amount;
        } else {
            market.totalNo += amount;
        }
        
        emit StakePlaced(marketId, msg.sender, isYes, amount);
    }
    
    /**
     * @notice Resolve market outcome (creator only, after deadline)
     * @param marketId The market to resolve
     * @param outcome True if YES wins, false if NO wins
     */
    function resolve(uint256 marketId, bool outcome) external nonReentrant {
        Market storage market = markets[marketId];
        require(msg.sender == market.creator, "Only creator can resolve");
        require(block.timestamp >= market.resolutionDeadline, "Too early");
        require(!market.resolved, "Already resolved");
        
        market.resolved = true;
        market.outcome = outcome;
        market.resolvedAt = block.timestamp;
        
        emit MarketResolved(marketId, msg.sender, outcome);
    }
    
    /**
     * @notice Dispute a resolution (within dispute window)
     * @param marketId The market to dispute
     */
    function dispute(uint256 marketId) external nonReentrant {
        Market storage market = markets[marketId];
        require(market.resolved, "Not resolved yet");
        require(!market.disputed, "Already disputed");
        require(block.timestamp <= market.resolvedAt + DISPUTE_WINDOW, "Dispute window closed");
        
        // Transfer dispute bond
        require(usdc.transferFrom(msg.sender, address(this), DISPUTE_BOND), "Dispute bond failed");
        
        market.disputed = true;
        market.disputer = msg.sender;
        
        emit MarketDisputed(marketId, msg.sender);
    }
    
    /**
     * @notice Claim winnings after resolution (and dispute window)
     * @param marketId The market to claim from
     */
    function claim(uint256 marketId) external nonReentrant {
        Market storage market = markets[marketId];
        require(market.resolved, "Not resolved");
        require(!claimed[marketId][msg.sender], "Already claimed");
        
        // If disputed, split pool 50/50 between YES and NO stakers (simplified resolution)
        if (market.disputed) {
            uint256 yesStake = stakes[marketId][msg.sender][true];
            uint256 noStake = stakes[marketId][msg.sender][false];
            require(yesStake > 0 || noStake > 0, "No stake");
            
            claimed[marketId][msg.sender] = true;
            
            uint256 totalPool = market.totalYes + market.totalNo;
            uint256 payout = 0;
            
            // Each side gets their proportional share of half the pool
            if (yesStake > 0 && market.totalYes > 0) {
                payout += (yesStake * totalPool) / (2 * market.totalYes);
            }
            if (noStake > 0 && market.totalNo > 0) {
                payout += (noStake * totalPool) / (2 * market.totalNo);
            }
            
            if (payout > 0) {
                require(usdc.transfer(msg.sender, payout), "Payout failed");
                emit WinningsClaimed(marketId, msg.sender, payout);
            }
            return;
        }
        
        // Normal resolution - must wait for dispute window
        require(block.timestamp > market.resolvedAt + DISPUTE_WINDOW, "Dispute window active");
        
        uint256 userStake = stakes[marketId][msg.sender][market.outcome];
        require(userStake > 0, "No winning stake");
        
        claimed[marketId][msg.sender] = true;
        
        uint256 totalPool = market.totalYes + market.totalNo;
        uint256 winningSide = market.outcome ? market.totalYes : market.totalNo;
        
        // Payout = (userStake / winningSide) * totalPool
        uint256 payout = (userStake * totalPool) / winningSide;
        
        require(usdc.transfer(msg.sender, payout), "Payout failed");
        
        emit WinningsClaimed(marketId, msg.sender, payout);
    }
    
    /**
     * @notice Creator can reclaim bond after successful resolution (no dispute)
     * @param marketId The market to reclaim bond from
     */
    function reclaimBond(uint256 marketId) external nonReentrant {
        Market storage market = markets[marketId];
        require(msg.sender == market.creator, "Only creator");
        require(market.resolved, "Not resolved");
        require(!market.disputed, "Was disputed");
        require(block.timestamp > market.resolvedAt + DISPUTE_WINDOW, "Dispute window active");
        
        // Return resolution bond to creator
        require(usdc.transfer(market.creator, RESOLUTION_BOND), "Bond return failed");
    }
    
    // View functions for agents
    
    function getMarket(uint256 marketId) external view returns (
        string memory question,
        address creator,
        uint256 resolutionDeadline,
        uint256 totalYes,
        uint256 totalNo,
        bool resolved,
        bool outcome,
        bool disputed
    ) {
        Market storage m = markets[marketId];
        return (
            m.question,
            m.creator,
            m.resolutionDeadline,
            m.totalYes,
            m.totalNo,
            m.resolved,
            m.outcome,
            m.disputed
        );
    }
    
    function getUserStake(uint256 marketId, address user) external view returns (
        uint256 yesStake,
        uint256 noStake
    ) {
        return (
            stakes[marketId][user][true],
            stakes[marketId][user][false]
        );
    }
}
