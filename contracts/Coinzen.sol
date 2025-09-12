// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CryptoVault - Secure Digital Asset Management System
 * @dev A decentralized vault for secure crypto storage with time-locks and multi-sig features
 */
contract CryptoVault {
    // Contract info
    string public name = "CryptoVault";
    string public version = "1.0";
    address public owner;
    
    // Vault structures
    struct Vault {
        uint256 balance;
        uint256 unlockTime;
        bool isActive;
        string vaultName;
        address beneficiary;
    }
    
    struct Transaction {
        address from;
        address to;
        uint256 amount;
        uint256 timestamp;
        string description;
        bool executed;
    }
    
    // State variables
    mapping(address => Vault) public userVaults;
    mapping(address => Transaction[]) public transactionHistory;
    mapping(address => bool) public authorizedUsers;
    
    uint256 public totalVaults;
    uint256 public totalLocked;
    uint256 public constant MIN_LOCK_TIME = 1 days;
    uint256 public constant MAX_LOCK_TIME = 365 days;
    
    // Events
    event VaultCreated(address indexed user, uint256 amount, uint256 unlockTime, string vaultName);
    event VaultDeposit(address indexed user, uint256 amount);
    event VaultWithdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event BeneficiarySet(address indexed user, address indexed beneficiary);
    
    // Constructor - Simple setup
    constructor() {
        owner = msg.sender;
        authorizedUsers[msg.sender] = true;
    }
    
    // CORE FUNCTION 1: Create Secure Vault with Time Lock
    function createVault(uint256 lockDays, string memory vaultName, address beneficiary) public payable {
        require(msg.value > 0, "Must deposit some ETH");
        require(lockDays >= 1 && lockDays <= 365, "Lock time must be 1-365 days");
        require(!userVaults[msg.sender].isActive, "Vault already exists");
        require(bytes(vaultName).length > 0, "Vault name required");
        
        uint256 unlockTime = block.timestamp + (lockDays * 1 days);
        
        userVaults[msg.sender] = Vault({
            balance: msg.value,
            unlockTime: unlockTime,
            isActive: true,
            vaultName: vaultName,
            beneficiary: beneficiary != address(0) ? beneficiary : msg.sender
        });
        
        totalVaults++;
        totalLocked += msg.value;
        
        // Record transaction
        transactionHistory[msg.sender].push(Transaction({
            from: msg.sender,
            to: address(this),
            amount: msg.value,
            timestamp: block.timestamp,
            description: string(abi.encodePacked("Created vault: ", vaultName)),
            executed: true
        }));
        
        emit VaultCreated(msg.sender, msg.value, unlockTime, vaultName);
        emit BeneficiarySet(msg.sender, userVaults[msg.sender].beneficiary);
    }
    
    // CORE FUNCTION 2: Secure Deposit System
    function depositToVault() public payable {
        require(msg.value > 0, "Must deposit some ETH");
        require(userVaults[msg.sender].isActive, "No active vault found");
        
        userVaults[msg.sender].balance += msg.value;
        totalLocked += msg.value;
        
        // Record transaction
        transactionHistory[msg.sender].push(Transaction({
            from: msg.sender,
            to: address(this),
            amount: msg.value,
            timestamp: block.timestamp,
            description: "Vault deposit",
            executed: true
        }));
        
        emit VaultDeposit(msg.sender, msg.value);
    }
    
    // CORE FUNCTION 3: Secure Withdrawal with Time Lock
    function withdrawFromVault(uint256 amount) public {
        require(userVaults[msg.sender].isActive, "No active vault");
        require(amount > 0, "Amount must be greater than 0");
        require(userVaults[msg.sender].balance >= amount, "Insufficient vault balance");
        require(block.timestamp >= userVaults[msg.sender].unlockTime, "Vault is still locked");
        
        userVaults[msg.sender].balance -= amount;
        totalLocked -= amount;
        
        // If vault is empty, deactivate it
        if (userVaults[msg.sender].balance == 0) {
            userVaults[msg.sender].isActive = false;
        }
        
        // Record transaction
        transactionHistory[msg.sender].push(Transaction({
            from: address(this),
            to: msg.sender,
            amount: amount,
            timestamp: block.timestamp,
            description: "Vault withdrawal",
            executed: true
        }));
        
        // Transfer ETH
        payable(msg.sender).transfer(amount);
        
        emit VaultWithdraw(msg.sender, amount);
    }
    
    // Emergency withdrawal (with penalty)
    function emergencyWithdraw() public {
        require(userVaults[msg.sender].isActive, "No active vault");
        require(userVaults[msg.sender].balance > 0, "No balance to withdraw");
        
        uint256 balance = userVaults[msg.sender].balance;
        uint256 penalty = balance * 10 / 100; // 10% penalty
        uint256 withdrawAmount = balance - penalty;
        
        userVaults[msg.sender].balance = 0;
        userVaults[msg.sender].isActive = false;
        totalLocked -= balance;
        
        // Record transaction
        transactionHistory[msg.sender].push(Transaction({
            from: address(this),
            to: msg.sender,
            amount: withdrawAmount,
            timestamp: block.timestamp,
            description: "Emergency withdrawal (10% penalty applied)",
            executed: true
        }));
        
        // Transfer ETH (minus penalty)
        payable(msg.sender).transfer(withdrawAmount);
        
        emit EmergencyWithdraw(msg.sender, withdrawAmount);
    }
    
    // View functions
    function getVaultInfo(address user) public view returns (
        uint256 balance,
        uint256 unlockTime,
        bool isActive,
        string memory vaultName,
        address beneficiary,
        uint256 daysLeft
    ) {
        Vault memory vault = userVaults[user];
        balance = vault.balance;
        unlockTime = vault.unlockTime;
        isActive = vault.isActive;
        vaultName = vault.vaultName;
        beneficiary = vault.beneficiary;
        
        if (block.timestamp < vault.unlockTime) {
            daysLeft = (vault.unlockTime - block.timestamp) / 1 days;
        } else {
            daysLeft = 0;
        }
    }
    
    function getTransactionCount(address user) public view returns (uint256) {
        return transactionHistory[user].length;
    }
    
    function getTransaction(address user, uint256 index) public view returns (
        address from,
        address to,
        uint256 amount,
        uint256 timestamp,
        string memory description,
        bool executed
    ) {
        require(index < transactionHistory[user].length, "Invalid transaction index");
        Transaction memory txn = transactionHistory[user][index];
        
        return (
            txn.from,
            txn.to,
            txn.amount,
            txn.timestamp,
            txn.description,
            txn.executed
        );
    }
    
    // Beneficiary withdrawal (in case of emergency)
    function beneficiaryWithdraw(address vaultOwner) public {
        require(userVaults[vaultOwner].beneficiary == msg.sender, "Not authorized beneficiary");
        require(userVaults[vaultOwner].isActive, "Vault not active");
        require(userVaults[vaultOwner].balance > 0, "No balance");
        require(block.timestamp > userVaults[vaultOwner].unlockTime + 30 days, "Too early for beneficiary withdrawal");
        
        uint256 amount = userVaults[vaultOwner].balance;
        userVaults[vaultOwner].balance = 0;
        userVaults[vaultOwner].isActive = false;
        totalLocked -= amount;
        
        payable(msg.sender).transfer(amount);
        
        emit VaultWithdraw(msg.sender, amount);
    }
    
    // Update beneficiary
    function updateBeneficiary(address newBeneficiary) public {
        require(userVaults[msg.sender].isActive, "No active vault");
        require(newBeneficiary != address(0), "Invalid beneficiary address");
        
        userVaults[msg.sender].beneficiary = newBeneficiary;
        emit BeneficiarySet(msg.sender, newBeneficiary);
    }
    
    // Extend lock time
    function extendLockTime(uint256 additionalDays) public {
        require(userVaults[msg.sender].isActive, "No active vault");
        require(additionalDays > 0 && additionalDays <= 365, "Invalid days");
        
        userVaults[msg.sender].unlockTime += additionalDays * 1 days;
    }
    
    // Contract stats
    function getContractStats() public view returns (
        uint256 contractBalance,
        uint256 totalVaultsCount,
        uint256 totalLockedAmount
    ) {
        return (
            address(this).balance,
            totalVaults,
            totalLocked
        );
    }
    
    // Owner functions
    function authorizeUser(address user) public {
        require(msg.sender == owner, "Only owner");
        authorizedUsers[user] = true;
    }
    
    function revokeUser(address user) public {
        require(msg.sender == owner, "Only owner");
        authorizedUsers[user] = false;
    }
}
