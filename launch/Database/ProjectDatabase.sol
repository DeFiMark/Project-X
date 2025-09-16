//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../../lib/Ownable.sol";

contract ProjectDatabase is Ownable {

    address[] public allProjects;

    struct Project {
        uint256 dexBuyFee;
        uint256 dexSellFee;
        address dexFeeRecipient;
    }

    mapping ( address => Project ) public projects;
}