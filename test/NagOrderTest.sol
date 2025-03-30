// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/NagOrder.sol";
import "solmate/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("MockAPT", "MAPT", 18) {}
    
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract NagOrderTest is Test {
    NagOrder public nagOrder;
    MockERC20 public aptosCoin;
    
    address user1 = address(0x1);
    address user2 = address(0x2);
    address relay = address(0x3);

    function setUp() public {
        aptosCoin = new MockERC20();
        nagOrder = new NagOrder(address(aptosCoin));
        
        // 初始化代币
        aptosCoin.mint(user1, 1000 ether);
        aptosCoin.mint(user2, 1000 ether);
        
        // 授权合约使用代币
        vm.prank(user1);
        aptosCoin.approve(address(nagOrder), type(uint256).max);
        
        vm.prank(user2);
        aptosCoin.approve(address(nagOrder), type(uint256).max);
    }

    // 测试创建订单
    function testPullOrder() public {
        vm.prank(user1);
        nagOrder.pull(123, _toUint64Array([456]), 10, 20, 30);

        // 验证订单信息
        NagOrder.Order memory order = nagOrder.orderLists(user1, 0);
        assertEq(order.modelHash, 123);
        assertEq(order.relayPubkeyList[0], 456);
        assertEq(order.status, 0);
        
        // 验证资金锁定
        assertEq(aptosCoin.balanceOf(address(nagOrder)), 60);
        assertEq(aptosCoin.balanceOf(user1), 1000 ether - 60);
    }

    // 测试增加保证金
    function testRaisePayment() public {
        testPullOrder(); // 先创建订单
        
        vm.prank(user1);
        nagOrder.raisePayment(0, 5, 5, 5);

        NagOrder.Order memory order = nagOrder.orderLists(user1, 0);
        assertEq(order.down, 15);
        assertEq(order.cost, 25);
        assertEq(order.tip, 35);
        assertEq(aptosCoin.balanceOf(address(nagOrder)), 60 + 15);
    }

    // 测试接单流程
    function testTakeOrder() public {
        testPullOrder();
        
        vm.prank(relay);
        nagOrder.takeOrder(0, user1, 456, 100);

        NagOrder.Order memory order = nagOrder.orderLists(user1, 0);
        assertEq(order.status, 1);
        assertEq(order.taker, relay);
        assertEq(order.product, 100);
        assertEq(aptosCoin.balanceOf(relay), 10); // 收到down payment
    }

    // 测试完成订单
    function testCompleteOrder() public {
        testTakeOrder();
        
        // 确认收货
        vm.prank(user1);
        nagOrder.confirmReceived(0);
        
        // 完成订单（正确参数）
        vm.prank(relay);
        nagOrder.completeOrder(0, user1, 10, 10);

        NagOrder.Order memory order = nagOrder.orderLists(user1, 0);
        assertEq(order.status, 3);
        assertEq(aptosCoin.balanceOf(relay), 10 + 20 + 30); // 收到cost + tip
    }

    // 测试失败场景
    function testFailInvalidTakeOrder() public {
        testPullOrder();
        
        // 使用错误的中继公钥
        vm.prank(relay);
        nagOrder.takeOrder(0, user1, 999, 100);
    }

    function testOrderLifecycle() public {
        // 完整生命周期测试
        testPullOrder();
        testRaisePayment();
        testTakeOrder();
        testCompleteOrder();
        
        // 最终验证
        assertEq(aptosCoin.balanceOf(address(nagOrder)), 0);
        assertEq(aptosCoin.balanceOf(relay), 60 + 15); // down + cost + tip
    }

    // 辅助函数：转换数组类型
    function _toUint64Array(uint64[] memory arr) private pure returns (uint64[] memory) {
        return arr;
    }
}