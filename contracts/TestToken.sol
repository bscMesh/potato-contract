// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;
import "./libs/BEP20.sol";

// PotatoToken.
contract TestToken is BEP20{

	constructor(string memory tokenName, string memory tokenSymbol) BEP20(tokenName, tokenSymbol){}
	
	uint constant MaxSupply = 80000 * 1e18;
    using SafeMath for uint256;
    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public {
		uint mintAmount = _amount;
		
		//limit max supply
		/*
		uint remainSupply = MaxSupply - totalSupply();
		if(mintAmount > remainSupply){
			mintAmount = remainSupply;
		}
		*/
		
        _mint(_to, mintAmount);
    }

}