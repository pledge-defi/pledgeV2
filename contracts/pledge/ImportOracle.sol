// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../interface/IBscPledgeOracle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ImportOracle is Ownable{

    IBscPledgeOracle internal _oracle;

    function oraclegetPrices(uint256[] memory assets) internal view returns (uint256[]memory){
        uint256[] memory prices = _oracle.getPrices(assets);
        uint256 len = assets.length;
        for (uint i=0;i<len;i++){
            require(prices[i] >= 100 && prices[i] <= 1e30,"oracle price error");
        }
        return prices;
    }

    function oraclePrice(address asset) internal view returns (uint256){
        uint256 price = _oracle.getPrice(asset);
        require(price >= 100 && price <= 1e30,"oracle price error");
        return price;
    }

    function oracleUnderlyingPrice(uint256 cToken) internal view returns (uint256){
        uint256 price = _oracle.getUnderlyingPrice(cToken);
        require(price >= 100 && price <= 1e30,"oracle price error");
        return price;
    }


    function getOracleAddress() public view returns(address){
        return address(_oracle);
    }

    function setOracleAddress(address oracle)public onlyOwner{
        _oracle = IBscPledgeOracle(oracle);
    }
}
