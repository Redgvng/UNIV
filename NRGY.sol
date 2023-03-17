// SPDX-License-Identifier: UNLICENSED
/*
 *
 * =======================================================================================/////
 * ======================================================================================/=////
 * =====================================================================================/=/=///
 * ====================================================================================/=/=/=//
 * ==================================//==========//=========//==========================/=/=/==
 * ===================================//=========//========//============================/=/===
 * ====================================//========//=======//==============================/====
 * =====================================//=======//======//====================================
 * ======================================//======//=====//=====================================
 * =======================================//=====//====//======================================
 * ========================================//====//===//=======================================
 * ==========================////////////////////////////////////////////======================
 * ========================================//////////////======================================
 * ========================================//////////////======================================
 * =======================================//=//////////=//=====================================
 * ======================================//==//////////==//====================================
 * =====================================//===//////////===//===================================
 * ====================================//====//////////====//==================================
 * ===================================//=====//////////=====//=================================
 * ==================================//======//////////======//================================
 * ==========================================//////////=======//===============================
 * ==========================================//////////========================================
 * ==========================================//////////========================================
 * ==========================================//////////========================================
 * ==========================================//////////========================================
 * ==========================================//////////========================================
 * ==========================================//////////========================================
 * ==========================================//////////========================================
 * ==========================================//////////========================================
 * ==========================================//////////========================================
 * ==========================================//////////========================================
 * ==========================================//////////========================================
*/


pragma solidity ^0.8.11;

import "Ownable.sol";
import "ERC20.sol";
import "ERC20Burnable.sol";
import "IPair.sol";
import "OwnerRecovery.sol";
import "LiquidityPoolManagerImplementationPointer.sol";
import "WalletObserverImplementationPointer.sol";

contract NRGY is
    ERC20,
    ERC20Burnable,
    Ownable,
    OwnerRecovery,
    LiquidityPoolManagerImplementationPointer,
    WalletObserverImplementationPointer
{
    address public immutable turbinesManager;
    uint256 public sellFeesAmount;
    address public treasury;
    mapping (address => bool) public excludedFromFees;

    modifier onlyTurbinesManager() {
        address sender = _msgSender();
        require(
            sender == address(turbinesManager),
            "Implementations: Not turbinesManager"
        );
        _;
    }

    constructor(address _turbinesManager,address _treasury) ERC20("ENERGY", "NRGY") {
        require(
            _turbinesManager != address(0),
            "Implementations: turbinesManager is not set"
        );
        turbinesManager = _turbinesManager;
        _mint(owner(), 42_000_000_000 * (10**18));
        setTreasury(_treasury);
        setFeesAmount(30);
    }

     function setFeesAmount(uint _sellFeesAmount) public onlyOwner {
        require(_sellFeesAmount <= 150, "fees too high");
        sellFeesAmount = _sellFeesAmount;
    }

    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        if (address(walletObserver) != address(0)) {
            walletObserver.beforeTokenTransfer(_msgSender(), from, to, amount);
        }
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._afterTokenTransfer(from, to, amount);
        if (address(liquidityPoolManager) != address(0)) {
            liquidityPoolManager.afterTokenTransfer(_msgSender());
        }
    }

    function accountBurn(address account, uint256 amount)
        external
        onlyTurbinesManager
    {
        // Note: _burn will call _beforeTokenTransfer which will ensure no denied addresses can create cargos
        // effectively protecting TurbinesManager from suspicious addresses
        super._burn(account, amount);
    }

    function accountReward(address account, uint256 amount)
        external
        onlyTurbinesManager
    {
        require(
            address(liquidityPoolManager) != account,
            "Wind: Use liquidityReward to reward liquidity"
        );
        super._mint(account, amount);
    }

    

    function liquidityReward(uint256 amount) external onlyTurbinesManager {
        require(
            address(liquidityPoolManager) != address(0),
            "Wind: LiquidityPoolManager is not set"
        );
        super._mint(address(liquidityPoolManager), amount);
    }


    function transfer(address recipient, uint256 amount) public override returns (bool) {
        return _transferTaxOverride(_msgSender(), recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transferTaxOverride(sender, recipient, amount);

        uint256 currentAllowance = allowance(sender,_msgSender());
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    // exclude addresses from fees (for exemple to deposit the initial liquidity without fees)
    function setFeesExcluded(address _addr, bool _isExcluded) external onlyOwner {
        excludedFromFees[_addr] = _isExcluded;
    }

    function _transferTaxOverride(address sender, address recipient, uint256 amount) internal returns (bool) {
        if (!excludedFromFees[sender]) {
            uint _transferAmount;

            if (isNRGYLiquidityPool(recipient)) { // if the recipient address is a liquidity pool, apply sell fee
                uint _fees = (amount * sellFeesAmount) / 1000;
                _transferAmount = amount - _fees;
                _transfer(sender, treasury, _fees); // transfer fee to treasury address
            }else {
                _transferAmount = amount;
            }
            _transfer(sender, recipient, _transferAmount);
        } else {
            _transfer(sender, recipient, amount);
        }
        return true;
    }


    // retreive token from pool contract (with getter function)
    function getPoolToken(address pool, string memory signature, function() external view returns(address) getter) private returns (address token) {
        (bool success, ) = pool.call(abi.encodeWithSignature(signature)); // if the call succeed (pool address have the "signature" method or "pool" is an EOA)
        if (success) {
            if (Address.isContract(pool)) { // verify that the pool is a contract (constructor can bypass this but its not dangerous)
                return getter();
            }
        }
    }

    // return true if the "_recipient" address is a FEAR liquidity pool
    function isNRGYLiquidityPool(address _recipient) private returns (bool) {
        address token0 = getPoolToken(_recipient, "token0()", IPair(_recipient).token0);
        address token1 = getPoolToken(_recipient, "token1()", IPair(_recipient).token1);

        return (token0 == address(this) || token1 == address(this));
    }
}