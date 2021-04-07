// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;
import "./libs/BEP20.sol";

// PotatoToken.
contract PotatoToken is BEP20('Potato', 'PTT') {

	uint constant MaxSupply = 3000000 * 1e18;
    using SafeMath for uint256;
    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
		uint mintAmount = _amount;
		uint remainSupply = MaxSupply - totalSupply();
		if(mintAmount > remainSupply){
			mintAmount = remainSupply;
		}
        _mint(_to, mintAmount);
    }

}