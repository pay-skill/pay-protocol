// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PayTab} from "../src/PayTab.sol";
import {PayFee} from "../src/PayFee.sol";
import {PayTypes} from "../src/libraries/PayTypes.sol";
import {PayErrors} from "../src/libraries/PayErrors.sol";
import {PayEvents} from "../src/libraries/PayEvents.sol";

/// @title MockUSDCTopUp
contract MockUSDCTopUp {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (balanceOf[msg.sender] < amount) return false;
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (balanceOf[from] < amount) return false;
        if (allowance[from][msg.sender] < amount) return false;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }

    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external pure {}
}

/// @title PayTabTopUpTest
/// @notice Unit + fuzz tests for PayTab.topUpTab and topUpTabFor
contract PayTabTopUpTest is Test {
    PayTab internal tab;
    PayFee internal fee;
    MockUSDCTopUp internal usdc;

    address internal owner = makeAddr("owner");
    address internal relayer = makeAddr("relayer");
    address internal feeWallet = makeAddr("feeWallet");
    address internal agent = makeAddr("agent");
    address internal provider = makeAddr("provider");
    address internal stranger = makeAddr("stranger");

    bytes32 constant TAB_ID = bytes32("tab-001");
    uint96 constant TAB_AMOUNT = 50e6; // $50
    uint96 constant MAX_CHARGE = 10e6;

    uint96 internal tabBalance;

    function setUp() public {
        usdc = new MockUSDCTopUp();

        PayFee feeImpl = new PayFee();
        bytes memory data = abi.encodeCall(feeImpl.initialize, (owner));
        fee = PayFee(address(new ERC1967Proxy(address(feeImpl), data)));

        tab = new PayTab(address(usdc), address(fee), feeWallet, relayer);

        vm.prank(owner);
        fee.authorizeCaller(address(tab));

        usdc.mint(agent, 1_000_000e6);
        vm.prank(agent);
        usdc.approve(address(tab), type(uint256).max);

        vm.prank(agent);
        tab.openTab(TAB_ID, provider, TAB_AMOUNT, MAX_CHARGE);
        tabBalance = tab.getTab(TAB_ID).amount;
    }

    // =========================================================================
    // topUpTab — happy path
    // =========================================================================

    function test_topUpTab_increasesBalance() public {
        uint96 topUp = 20e6;

        vm.prank(agent);
        tab.topUpTab(TAB_ID, topUp);

        assertEq(tab.getTab(TAB_ID).amount, tabBalance + topUp);
    }

    function test_topUpTab_noActivationFee() public {
        uint96 topUp = 30e6;
        uint96 activationFeeBefore = tab.getTab(TAB_ID).activationFee;

        uint256 agentBefore = usdc.balanceOf(agent);
        uint256 feeWalletBefore = usdc.balanceOf(feeWallet);

        vm.prank(agent);
        tab.topUpTab(TAB_ID, topUp);

        // Agent loses exactly the top-up amount (no fee)
        assertEq(usdc.balanceOf(agent), agentBefore - topUp);
        // Fee wallet unchanged
        assertEq(usdc.balanceOf(feeWallet), feeWalletBefore);
        // Activation fee unchanged
        assertEq(tab.getTab(TAB_ID).activationFee, activationFeeBefore);
    }

    function test_topUpTab_contractReceivesUsdc() public {
        uint96 topUp = 15e6;
        uint256 contractBefore = usdc.balanceOf(address(tab));

        vm.prank(agent);
        tab.topUpTab(TAB_ID, topUp);

        assertEq(usdc.balanceOf(address(tab)), contractBefore + topUp);
    }

    function test_topUpTab_emitsEvent() public {
        uint96 topUp = 10e6;
        uint96 expectedBalance = tabBalance + topUp;

        vm.expectEmit(true, false, false, true);
        emit PayEvents.TabToppedUp(TAB_ID, topUp, expectedBalance);

        vm.prank(agent);
        tab.topUpTab(TAB_ID, topUp);
    }

    function test_topUpTab_multipleTopUps() public {
        vm.startPrank(agent);
        tab.topUpTab(TAB_ID, 5e6);
        tab.topUpTab(TAB_ID, 10e6);
        tab.topUpTab(TAB_ID, 3e6);
        vm.stopPrank();

        assertEq(tab.getTab(TAB_ID).amount, tabBalance + 18e6);
    }

    function test_topUpTab_afterCharges() public {
        // Charge some, then top up
        vm.prank(relayer);
        tab.chargeTab(TAB_ID, 10e6);

        uint96 balanceAfterCharge = tab.getTab(TAB_ID).amount;

        vm.prank(agent);
        tab.topUpTab(TAB_ID, 20e6);

        assertEq(tab.getTab(TAB_ID).amount, balanceAfterCharge + 20e6);
        // totalCharged unchanged
        assertEq(tab.getTab(TAB_ID).totalCharged, 10e6);
    }

    // =========================================================================
    // topUpTabFor — happy path
    // =========================================================================

    function test_topUpTabFor_works() public {
        uint96 topUp = 25e6;

        vm.prank(relayer);
        tab.topUpTabFor(agent, TAB_ID, topUp);

        assertEq(tab.getTab(TAB_ID).amount, tabBalance + topUp);
    }

    // =========================================================================
    // topUpTab — reverts
    // =========================================================================

    function test_topUpTab_revertsOnNonexistentTab() public {
        bytes32 fakeId = bytes32("nonexistent");
        vm.expectRevert(abi.encodeWithSelector(PayErrors.TabNotFound.selector, fakeId));
        vm.prank(agent);
        tab.topUpTab(fakeId, 5e6);
    }

    function test_topUpTab_revertsOnClosedTab() public {
        vm.prank(agent);
        tab.closeTab(TAB_ID);

        vm.expectRevert(abi.encodeWithSelector(PayErrors.TabClosed.selector, TAB_ID));
        vm.prank(agent);
        tab.topUpTab(TAB_ID, 5e6);
    }

    function test_topUpTab_revertsOnZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(PayErrors.ZeroAmount.selector));
        vm.prank(agent);
        tab.topUpTab(TAB_ID, 0);
    }

    function test_topUpTab_revertsForNonAgent() public {
        // Provider cannot top up
        vm.expectRevert(abi.encodeWithSelector(PayErrors.Unauthorized.selector, provider));
        vm.prank(provider);
        tab.topUpTab(TAB_ID, 5e6);
    }

    function test_topUpTab_revertsForStranger() public {
        vm.expectRevert(abi.encodeWithSelector(PayErrors.Unauthorized.selector, stranger));
        vm.prank(stranger);
        tab.topUpTab(TAB_ID, 5e6);
    }

    function test_topUpTab_revertsOnInsufficientBalance() public {
        address broke = makeAddr("broke");
        // Open a tab for broke, then try to top up with no funds
        usdc.mint(broke, 10e6);
        vm.prank(broke);
        usdc.approve(address(tab), type(uint256).max);
        vm.prank(broke);
        tab.openTab(bytes32("broke-tab"), provider, 10e6, 10e6);

        vm.expectRevert(abi.encodeWithSelector(PayErrors.TransferFailed.selector));
        vm.prank(broke);
        tab.topUpTab(bytes32("broke-tab"), 5e6);
    }

    function test_topUpTabFor_revertsForNonRelayer() public {
        vm.expectRevert(abi.encodeWithSelector(PayErrors.Unauthorized.selector, stranger));
        vm.prank(stranger);
        tab.topUpTabFor(agent, TAB_ID, 5e6);
    }

    function test_topUpTabFor_revertsOnZeroAgent() public {
        vm.expectRevert(abi.encodeWithSelector(PayErrors.ZeroAddress.selector));
        vm.prank(relayer);
        tab.topUpTabFor(address(0), TAB_ID, 5e6);
    }

    // =========================================================================
    // Fuzz: balance conservation through top-up
    // =========================================================================

    function testFuzz_topUpConservesUsdc(uint96 topUp) public {
        topUp = uint96(bound(topUp, 1, 1_000_000e6));

        usdc.mint(agent, topUp); // ensure enough

        uint256 totalBefore = usdc.balanceOf(agent) + usdc.balanceOf(address(tab)) + usdc.balanceOf(feeWallet);

        vm.prank(agent);
        tab.topUpTab(TAB_ID, topUp);

        uint256 totalAfter = usdc.balanceOf(agent) + usdc.balanceOf(address(tab)) + usdc.balanceOf(feeWallet);
        assertEq(totalAfter, totalBefore, "USDC must be conserved");
    }

    function testFuzz_topUpIncreasesBalanceExactly(uint96 topUp) public {
        topUp = uint96(bound(topUp, 1, 1_000_000e6));
        usdc.mint(agent, topUp);

        uint96 balanceBefore = tab.getTab(TAB_ID).amount;

        vm.prank(agent);
        tab.topUpTab(TAB_ID, topUp);

        assertEq(tab.getTab(TAB_ID).amount, balanceBefore + topUp, "balance must increase by exact top-up amount");
    }

    function testFuzz_topUpNoFee(uint96 topUp) public {
        topUp = uint96(bound(topUp, 1, 1_000_000e6));
        usdc.mint(agent, topUp);

        uint256 feeWalletBefore = usdc.balanceOf(feeWallet);

        vm.prank(agent);
        tab.topUpTab(TAB_ID, topUp);

        assertEq(usdc.balanceOf(feeWallet), feeWalletBefore, "feeWallet must not change on top-up");
    }
}
