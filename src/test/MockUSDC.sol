// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockUSDC
/// @notice Testnet-only USDC mock with open minting, EIP-2612 permit, and EIP-3009 receiveWithAuthorization.
/// @dev NOT for production. Anyone can mint. Signature verification is skipped for testnet simplicity.
///      The server faucet endpoint mints USDC to agent wallets on testnet.
contract MockUSDC {
    string public constant name = "USD Coin";
    string public constant symbol = "USDC";
    uint8 public constant decimals = 6;
    string public constant version = "2";

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // EIP-2612 permit nonce tracking
    mapping(address => uint256) private _permitNonces;

    // EIP-3009 nonce tracking
    mapping(bytes32 => bool) public authorizationUsed;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Mint USDC to any address. Open on testnet.
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "USDC: insufficient allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        return _transfer(from, to, amount);
    }

    /// @notice EIP-2612 permit. Testnet: skips signature verification, just sets allowance.
    /// @dev Increments nonce so acceptance tests can query nonces() and construct valid permits.
    function permit(address owner_, address spender, uint256 value, uint256, uint8, bytes32, bytes32) external {
        _permitNonces[owner_]++;
        allowance[owner_][spender] = value;
        emit Approval(owner_, spender, value);
    }

    /// @notice Returns the current permit nonce for an address (EIP-2612).
    function nonces(address owner_) external view returns (uint256) {
        return _permitNonces[owner_];
    }

    /// @notice Returns the EIP-712 domain separator.
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("USD Coin"),
                keccak256("2"),
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice EIP-3009 receiveWithAuthorization. Testnet: skips signature verification.
    /// @dev `to` must equal msg.sender (enforced by real USDC).
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256, /* validAfter */
        uint256, /* validBefore */
        bytes32 nonce,
        uint8, /* v */
        bytes32, /* r */
        bytes32 /* s */
    ) external {
        require(to == msg.sender, "MockUSDC: caller must be the payee");
        require(!authorizationUsed[nonce], "MockUSDC: authorization already used");
        authorizationUsed[nonce] = true;
        _transfer(from, to, value);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf[from] >= amount, "USDC: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
