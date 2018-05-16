/*

    Copyright 2018 dYdX Trading Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

*/
/**
 *
 */

pragma solidity 0.4.23;
pragma experimental "v0.5.0";

import { SafeMath } from "zeppelin-solidity/contracts/math/SafeMath.sol";
import { ERC20 }    from "../../../Kyber/ERC20Interface.sol";
import { HasNoContracts } from "zeppelin-solidity/contracts/ownership/HasNoContracts.sol";
import { HasNoEther } from "zeppelin-solidity/contracts/ownership/HasNoEther.sol";
import { KyberExchangeInterface } from "../../../interfaces/KyberExchangeInterface.sol";
import { MathHelpers } from "../../../lib/MathHelpers.sol";
import { TokenInteract } from "../../../lib/TokenInteract.sol";
import { ExchangeWrapper } from "../../interfaces/ExchangeWrapper.sol";
import { OnlyMargin } from "../../interfaces/OnlyMargin.sol";
import { WETH9 } from "../../../Kyber/WrappedEth.sol";


/**
 * @title KyberNetworkWrapper
 * @author dYdX
 *
 * dYdX ExchangeWrapper to interface with KyberNetwork
 */
contract KyberExchangeWrapper is
    HasNoEther,
    HasNoContracts,
    OnlyMargin,
    ExchangeWrapper
{
    using SafeMath for uint256;



    // ============ Structs ============


    //KyberOrder
    /**
     * [DYDX_PROXY description]
     * @type {[type]}
     */
    struct Order {
      address walletId;
      uint srcAmount; //amount taker has to offer
      uint maxDestAmount; //when using exchangeforAmount, if 0 then maxUint256
      uint256 minConversionRate; //1 for market price if not given
    }

    // ============ State Variables ============
    address public ETH_TOKEN_ADDRESS = 0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;
    address public DYDX_PROXY;
    address public KYBER_NETWORK;
    address public WRAPPED_ETH;
    /* address public ZERO_EX_PROXY;
    address public ZRX; */

    // ============ Constructor ============

    constructor(
        address margin,
        address dydxProxy,
        address kyber_network,
        address wrapped_eth
    )
        public
        OnlyMargin(margin)
    {
        DYDX_PROXY = dydxProxy;
        KYBER_NETWORK = kyber_network;
        WRAPPED_ETH = wrapped_eth;
        // The ZRX token does not decrement allowance if set to MAX_UINT
        // therefore setting it once to the maximum amount is sufficient
        // NOTE: this is *not* standard behavior for an ERC20, so do not rely on it for other tokens
      //  TokenInteract.approve(ZRX, ZERO_EX_PROXY, MathHelpers.maxUint256());
    }

    // ============ Margin-Only Functions ============
    /**
     * Exchange some amount of takerToken for makerToken.
     *
     * @param  makerToken           Address of makerToken, the token to receive
     * @param  takerToken           Address of takerToken, the token to pay
     * @param  tradeOriginator      The msg.sender of the first call into the dYdX contract
     * @param  requestedFillAmount  Amount of takerToken being paid
     * @param  orderData            Arbitrary bytes data for any information to pass to the exchange
     * @return                      The amount of makerToken received
     I need to find out a way to check whether or not either the maker
     or taker token are actually wrapped ether

     */
    function exchange(
        address makerToken,
        address takerToken,
        address tradeOriginator,
        uint256 requestedFillAmount,
        bytes orderData
    )
        external
        /* onlyMargin */
        returns (uint256)
        {
          Order memory order = parseOrder(orderData);
          assert(TokenInteract.balanceOf(takerToken, address(this)) >= requestedFillAmount);
          assert(requestedFillAmount > 0);
          //check if maker or taker are wrapped eth (but they cant both be ;))
          require( (makerToken!=takerToken) && (makerToken==WRAPPED_ETH || takerToken==WRAPPED_ETH) )
          uint256 receivedMakerTokenAmount;
          // 1st scenario: takerToken is Eth, and should be sent appropriately
          if (takerToken == WRAPPED_ETH) {

              receivedMakerTokenAmount = exchangefromWETH(
                    Order order,
                    address makerToken,
                    uint256 requestedFillAmount
                );
          }
          if (makerToken == WRAPPED_ETH) {
              receivedMakerTokenAmount = exchangeToWETH(
                Order order,
                address takerToken,
                uint256 requestedFillAmount
                )
          }
          return receivedMakerTokenAmount;
        }

    /**
     * Exchange takerToken for an exact amount of makerToken. Any extra makerToken exist
     * as a result of the trade will be left in the exchange wrapper
     *
     * @param  makerToken         Address of makerToken, the token to receive
     * @param  takerToken         Address of takerToken, the token to pay
     * @param  tradeOriginator    The msg.sender of the first call into the dYdX contract
     * @param  desiredMakerToken  Amount of makerToken requested
     * @param  orderData          Arbitrary bytes data for any information to pass to the exchange
     * @return                    The amount of takerToken used
     */
    function exchangeForAmount(
        address makerToken,
        address takerToken,
        address tradeOriginator,
        uint256 desiredMakerToken,
        bytes orderData
    )
        external
        /* onlyMargin */
        returns (uint256);

    // ============ Public Constant Functions ========
    /**
     * Get amount of makerToken that will be paid out by exchange for a given trade. Should match
     * the amount of makerToken returned by exchange
     *
     * @param  makerToken           Address of makerToken, the token to receive
     * @param  takerToken           Address of takerToken, the token to pay
     * @param  requestedFillAmount  Amount of takerToken being paid
     * @param  orderData            Arbitrary bytes data for any information to pass to the exchange
     * @return                      The amount of makerToken that would be received as a result of
     *                              taking this trade
     */
    function getTradeMakerTokenAmount(
        address makerToken,
        address takerToken,
        uint256 requestedFillAmount,
        bytes orderData
    )
        external
        view
        returns (uint256) {
          Order memory order = parseData(orderData);
          //before called, one of these token pairs needs to be WETH
          require((makerToken!=takerToken)&&(makerToken==WRAPPED_ETH||takerToken==WRAPPED_ETH));
          uint256 conversionRate;
          if(makerToken==WRAPPED_ETH) {
            conversionRate = getConversionRate(
                               ETH_TOKEN_ADDRESS,
                               takerToken,
                               requestedFillAmount
              );
          } else if(takerToken==WRAPPED_ETH) {
            conversionRate = getConversionRate(
                              makerToken,
                              ETH_TOKEN_ADDRESS,
                              requestedFillAmount
              );
          }
          return conversionRate;
        }

    /**
     *this function will query the getExpectedRate() function from the KyberNetworkWrapper
     * and return the slippagePrice, which is the worst case scenario for accuracy and ETH_TOKEN_ADDRESS
     * will multiply it by the desiredAmount
     */
    function getTakerTokenPrice(
        address makerToken,
        address takerToken,
        uint256 desiredMakerToken,
        bytes orderData
    )
        external
        view
        returns (uint256);
         {

         }

    /* function trade (
           ERC20 source -- taker token
           uint srcAmount -- amount to taker
           ERC20 dest -- maker tokens
           address destAddress -- destiantion of taker
           uint maxDestAmount -- ONLY for exchangeforAmount, otherwise maxUint256
           uint minConversionRate -- set to 1 for now (later when building out the interface)
           address walletId -- set to 0 for now
        ) */


    // =========== Internal Functions ============
    function exchangeFromWETH(
              Order order,
              address makerToken,
              uint256 requestedFillAmount
          )
          internal
          returns (uint256) {
              //unwrap ETH
              WETH9(WRAPPED_ETH).withdraw(requestedFillAmount);
              //dummy check to see if it sent through
              require(msg.value>0);
              //send trade through
              uint256 receivedMakerTokenAmount = KyberExchangeWrapper(KYBER_NETWORK).trade.value(msg.value)(
                                                          ETH_TOKEN_ADDRESS,
                                                          msg.value,
                                                          makerToken,
                                                          address(this),
                                                          MathHelpers.maxUint256(),
                                                          (order.minConversionRate ? order.minConversionRate : 1),
                                                          order.walletId
                                                          );
            return receivedMakerTokenAmount; 
          }

    function exchangeToWETH(
        Order order,
        address takerToken,
        uint256 requestedFillAmount
      )
      internal
      returns (uint256) {
        //received ETH in wei
        uint receivedMakerTokenAmount = KyberExchangeWrapper(KYBER_NETWORK).trade(
                                                    takerToken,
                                                    requestedFillAmount,
                                                    ETH_TOKEN_ADDRESS,
                                                    address(this),
                                                    MathHelpers.maxUint256(),
                                                    (order.minConversionRate ? order.minConversionRate : 1),
                                                    order.walletId
                                                    );
        //dummy check to see if eth was actually sent
        require(msg.value>0);
        WETH9(WRAPPED_ETH).deposit.value(msg.value);
        return receivedMakerTokenAmount;
      }
      /**
       *
       this function will call KyberNetwork's
       */

    function getConversionRate(
      address makerToken,
      address takerToken,
      uint256 requestedFillAmount
      )
      internal
      returns (uint) {
        (uint expectedPrice,uint slippagePrice) = KyberExchangeWrapper(KYBER_NETWORK).getExpectedRate(
                                                      takerToken,
                                                      makerToken,
                                                      requestedFillAmount);
        return slippagePrice;

      }

      function ensureAllowance(
        address token,
        address spender,
        uint256 requiredAmount
        )
        internal
        {
          if (TokenInteract.allowance(token,address(this),spender) >= requiredAmount) {
            return;
          }
          TokenInteract.approve(
            token,
            spender,
            MathHelpers.maxUint256()
            );
        }

    /* struct KyberOrder {
      uint srcAmount; //amount taker has to offer
      address taker; //destAddress
      uint maxDestAmount; //when using exchangeforAmount, otherwise max
      struct Order {
        address walletId;
        uint srcAmount; //amount taker has to offer
        uint maxDestAmount; //when using exchangeforAmount, if 0 then maxUint256
        uint256 minConversionRate; //1 for market price if not given
      }
    } */
    function parseOrder(
      bytes orderData
      )
    internal
    pure
    returns (Order memory)
    {
      Order memory order;
      /**
       * Total: 384 bytes
       * mstore stores 32 bytes at a time, so go in increments of 32 bytes
       *
       * NOTE: The first 32 bytes in an array store the length, so we start reading from 32
       */
      assembly {
        mstore(order,            mload(add(orderData,32))) //walletId
        mstore(add(order,32)     mload(add(orderData,64))) //srcAmount
        mstore(add(order,64)     mload(add(orderData,96))) //maxDestAmount
        mstore(add(order,96)     mload(add(orderData,128))) //minConversionRate
        }
      return order;
    }

}
