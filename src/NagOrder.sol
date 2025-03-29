// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract NagOrder {
    struct Order {
        uint64 orderId;
        uint8 status; // 0: Created, 1: Taken, 2: Confirmed, 3: Completed, 4: Failed
        uint64 modelHash;
        uint64[] relayPubkeyList;
        uint64 down;
        uint64 cost;
        uint64 tip;
        address taker;
        uint64 product;
    }

    mapping(address => Order[]) public orderLists;
    IERC20 public aptosCoin;

    event Pull(
        address indexed userAddress,
        uint64 indexed orderId,
        uint64 modelHash,
        uint64[] relayPubkeyList,
        uint64 down,
        uint64 cost,
        uint64 tip
    );

    event RaisePayment(
        address indexed userAddress,
        uint64 indexed orderId,
        uint64 modelHash,
        uint64[] relayPubkeyList,
        uint64 down,
        uint64 cost,
        uint64 tip
    );

    event TakeOrder(
        address indexed relayAddress,
        uint64 indexed orderId,
        address indexed orderAddress
    );

    event CompleteOrder(
        address indexed orderAddress,
        uint64 indexed orderId,
        uint64 prime1,
        uint64 prime2
    );

    constructor(address _aptosCoin) {
        aptosCoin = IERC20(_aptosCoin);
    }

    function pull(
        uint64 modelHash,
        uint64[] memory relayPubkeyList,
        uint64 down,
        uint64 cost,
        uint64 tip
    ) external {
        uint256 sum = down + cost + tip;
        require(aptosCoin.transferFrom(msg.sender, address(this), sum), "Payment failed");
        
        uint64 orderId = uint64(orderLists[msg.sender].length);
        orderLists[msg.sender].push(Order({
            orderId: orderId,
            status: 0,
            modelHash: modelHash,
            relayPubkeyList: relayPubkeyList,
            down: down,
            cost: cost,
            tip: tip,
            taker: address(0),
            product: 0
        }));

        emit Pull(msg.sender, orderId, modelHash, relayPubkeyList, down, cost, tip);
    }

    function raisePayment(
        uint64 orderId,
        uint64 down,
        uint64 cost,
        uint64 tip
    ) external {
        Order storage order = orderLists[msg.sender][orderId];
        require(order.status == 0, "Invalid status");

        uint256 sum = down + cost + tip;
        require(aptosCoin.transferFrom(msg.sender, address(this), sum), "Payment failed");

        order.down += down;
        order.cost += cost;
        order.tip += tip;

        emit RaisePayment(msg.sender, orderId, order.modelHash, order.relayPubkeyList, down, cost, tip);
    }

    function takeOrder(
        uint64 orderId,
        address orderAddress,
        uint64 relayPubkey,
        uint64 x
    ) external {
        Order storage order = orderLists[orderAddress][orderId];
        require(order.status == 0, "Invalid status");
        require(contains(order.relayPubkeyList, relayPubkey), "Invalid relay key");

        order.status = 1;
        order.taker = msg.sender;
        order.product = x;
        
        require(aptosCoin.transfer(msg.sender, order.down), "Down payment failed");

        emit TakeOrder(msg.sender, orderId, orderAddress);
    }

    function confirmReceived(uint64 orderId) external {
        Order storage order = orderLists[msg.sender][orderId];
        require(order.status == 1, "Invalid status");
        order.status = 2;
    }

    function completeOrder(
        uint64 orderId,
        address orderAddress,
        uint64 prime1,
        uint64 prime2
    ) external {
        Order storage order = orderLists[orderAddress][orderId];
        require(order.status == 2, "Invalid status");

        if (prime1 * prime2 == order.product) {
            order.status = 3;
            uint256 amount = order.cost + order.tip;
            require(aptosCoin.transfer(order.taker, amount), "Payment failed");
            emit CompleteOrder(orderAddress, orderId, prime1, prime2);
        } else {
            order.status = 4;
        }
    }

    function getOrderStatus(address userAddress, uint64 orderId) external view returns (uint8) {
        return orderLists[userAddress][orderId].status;
    }

    function contains(uint64[] memory list, uint64 key) private pure returns (bool) {
        for (uint i = 0; i < list.length; i++) {
            if (list[i] == key) return true;
        }
        return false;
    }
}