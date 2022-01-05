// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IDebtToken {
     /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

     /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Minting tokens for specific accounts.
     */
    function mint(address account, uint256 amount) external;

     /**
     * @dev Burning tokens for specific accounts.
     */
    function burn(address account, uint256 amount) external;

}