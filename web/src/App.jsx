import React, { useState, useEffect } from 'react';
import { ShoppingCart, Package, Package2, X, Trash2, CreditCard, Search, Wallet, Plus, Lock } from 'lucide-react';
import './App.css';

const App = () => {
  const [isOpen, setIsOpen] = useState(false);
  const [activeCategory, setActiveCategory] = useState('all');
  const [cart, setCart] = useState([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [notification, setNotification] = useState({ show: false, message: '', type: '' });
  const [showCheckoutModal, setShowCheckoutModal] = useState(false);
  const [shopItems, setShopItems] = useState([]);
  const [playerMoney, setPlayerMoney] = useState({ cash: 0, bank: 0 });
  const [customCurrencies, setCustomCurrencies] = useState({});
  const [shopLabel, setShopLabel] = useState('General Store');
  const [theme, setTheme] = useState({
    primary: '#4ade80',
    primaryDark: '#22c55e',
    primaryText: '#0f0f10'
  });
  const [categories, setCategories] = useState([]);

  useEffect(() => {
    const handleMessage = (event) => {
      const data = event.data;
      
      if (data.action === 'openShop') {
        setIsOpen(true);
        setShopItems(data.items || []);
        setPlayerMoney(data.money || { cash: 0, bank: 0 });
        setCustomCurrencies(data.customCurrencies || {});
        setShopLabel(data.shopLabel || 'General Store');
        setTheme(data.theme || {
          primary: '#4ade80',
          primaryDark: '#22c55e',
          primaryText: '#0f0f10'
        });
        
        const uniqueCategories = ['all'];
        const categorySet = new Set();
        
        (data.items || []).forEach(item => {
          if (item.category && !categorySet.has(item.category)) {
            categorySet.add(item.category);
            uniqueCategories.push(item.category);
          }
        });
        
        setCategories(uniqueCategories);
        setCart([]);
        setActiveCategory('all');
        setSearchQuery('');
        setShowCheckoutModal(false);
      } else if (data.action === 'closeShop') {
        setIsOpen(false);
        setShowCheckoutModal(false);
      }
    };

    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
  }, []);

  useEffect(() => {
    const handleKeyDown = (event) => {
      if (event.key === 'Escape' && isOpen) {
        closeShop();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen]);

  const filteredItems = shopItems.filter(item => {
    const matchesCategory = activeCategory === 'all' || item.category === activeCategory;
    const matchesSearch = item.label.toLowerCase().includes(searchQuery.toLowerCase());
    return matchesCategory && matchesSearch;
  });

  const showNotification = (message, type) => {
    setNotification({ show: true, message, type });
    setTimeout(() => setNotification({ show: false, message: '', type: '' }), 3000);
  };

  const closeShop = () => {
    setIsOpen(false);
    fetch(`https://${GetParentResourceName()}/closeShop`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({})
    });
  };

  const addToCart = (item) => {
    if (item.locked) {
      showNotification(item.lockReason || 'This item is locked', 'error');
      return;
    }

    const getItemCurrencyType = (itm) => {
      if (!itm.currency || itm.currency === 'cash' || itm.currency === 'bank') {
        return 'standard';
      }
      return itm.currency;
    };

    const itemCurrencyType = getItemCurrencyType(item);
    const cartCurrencyTypes = new Set(cart.map(c => getItemCurrencyType(c)));

    if (cartCurrencyTypes.size > 0 && !cartCurrencyTypes.has(itemCurrencyType)) {
      showNotification('Cannot mix different currency types in one purchase', 'error');
      return;
    }

    const existingItem = cart.find(cartItem => cartItem.item === item.item);
    if (existingItem) {
      setCart(cart.map(cartItem =>
        cartItem.item === item.item
          ? { ...cartItem, quantity: cartItem.quantity + 1 }
          : cartItem
      ));
      showNotification(`Added another ${item.label} to cart`, 'success');
    } else {
      setCart([...cart, { ...item, quantity: 1 }]);
      showNotification(`${item.label} added to cart`, 'success');
    }
  };

  const removeFromCart = (itemName) => {
    const item = cart.find(cartItem => cartItem.item === itemName);
    setCart(cart.filter(cartItem => cartItem.item !== itemName));
    showNotification(`${item.label} removed from cart`, 'info');
  };

  const updateQuantity = (itemName, delta) => {
    setCart(cart.map(item => {
      if (item.item === itemName) {
        const newQuantity = Math.max(1, item.quantity + delta);
        return { ...item, quantity: newQuantity };
      }
      return item;
    }));
  };

  const getTotalPrice = () => {
    return cart.reduce((total, item) => total + (item.price * item.quantity), 0);
  };

  const handleCheckout = () => {
    if (cart.length === 0) {
      showNotification('Your cart is empty', 'error');
      return;
    }
    setShowCheckoutModal(true);
  };

  const completePurchase = (paymentMethod) => {
    const total = getTotalPrice();
    const isCustomCurrency = customCurrencies[paymentMethod];
    
    if (isCustomCurrency) {
      if (customCurrencies[paymentMethod].count < total) {
        showNotification(`Insufficient ${customCurrencies[paymentMethod].label}`, 'error');
        return;
      }
    } else {
      if (playerMoney[paymentMethod] < total) {
        const displayName = paymentMethod === 'bank' ? 'Card' : 'Cash';
        showNotification(`Insufficient funds in ${displayName}`, 'error');
        return;
      }
    }

    fetch(`https://${GetParentResourceName()}/purchaseItems`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        items: cart,
        total: total,
        paymentMethod: paymentMethod
      })
    }).then(resp => resp.json()).then(data => {
      if (data.success) {
        let displayMessage;
        if (isCustomCurrency) {
          displayMessage = `Purchase successful! Paid ${total} ${customCurrencies[paymentMethod].label}`;
        } else {
          const displayName = paymentMethod === 'bank' ? 'Card' : 'Cash';
          displayMessage = `Purchase successful! Paid $${total} with ${displayName}`;
        }
        showNotification(displayMessage, 'success');
        setPlayerMoney(data.money);
        setCustomCurrencies(data.customCurrencies || {});
        setCart([]);
        setShowCheckoutModal(false);
      } else {
        showNotification(data.message || 'Purchase failed', 'error');
        if (data.money) setPlayerMoney(data.money);
        if (data.customCurrencies) setCustomCurrencies(data.customCurrencies);
      }
    });
  };

  const formatCategoryName = (category) => {
    if (category === 'all') return 'All Items';
    return category.charAt(0).toUpperCase() + category.slice(1);
  };

  if (!isOpen) return null;

  return (
    <div className="shop-container" style={{
      '--theme-primary': theme.primary,
      '--theme-primary-dark': theme.primaryDark,
      '--theme-primary-text': theme.primaryText
    }}>
      <div className="shop-header">
        <div className="header-content">
          <div className="header-icon">
            <ShoppingCart size={24} color="#ffffff" />
          </div>
          <div>
            <h1 className="header-title">{shopLabel}</h1>
          </div>
        </div>
        <button className="close-button" onClick={closeShop}>
          <X size={20} />
        </button>
      </div>

      <div className="main-content">
        <div className="shop-panel">
          <div className="categories-container">
            {categories.map(cat => (
              <button
                key={cat}
                onClick={() => setActiveCategory(cat)}
                className={`category-button ${activeCategory === cat ? 'active' : ''}`}
              >
                {formatCategoryName(cat)}
              </button>
            ))}
          </div>

          <div className="search-container">
            <div className="search-wrapper">
              <Search size={16} className="search-icon" />
              <input
                type="text"
                placeholder="Search items..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="search-input"
              />
            </div>
          </div>

          <div className="items-grid">
            {filteredItems.map((item, index) => (
              <div
                key={index}
                onClick={() => addToCart(item)}
                className={`shop-item ${item.locked ? 'locked' : ''}`}
              >
                {item.locked && (
                  <div className="lock-overlay">
                    <Lock size={32} />
                    <span className="lock-reason">{item.lockReason}</span>
                  </div>
                )}
                <div className="item-icon">
                  <img 
                    src={`nui://ox_inventory/web/images/${item.item}.png`}
                    alt={item.label}
                    onError={(e) => {
                      e.target.style.display = 'none';
                      e.target.nextSibling.style.display = 'block';
                    }}
                  />
                  <div className="item-icon-fallback" style={{ display: 'none' }}><Package2 /></div>
                </div>
                <h3 className="item-name">{item.label}</h3>
                <div className="item-price">
                  {item.currency && item.currency !== 'cash' && item.currency !== 'bank' 
                    ? `${item.price} ${item.currencyInfo?.label || item.currency}`
                    : `$${item.price}`
                  }
                </div>
                <button className="add-to-cart-btn">
                  <Plus size={16} />
                  Add to Cart
                </button>
              </div>
            ))}
          </div>
        </div>

        <div className="cart-panel">
          <div className="cart-header">
            <div className="cart-header-content">
              <ShoppingCart size={24} style={{ color: theme.primary }} />
              <h2 className="cart-title">Shopping Cart</h2>
            </div>
            <p className="cart-count">
              {cart.length} {cart.length === 1 ? 'item' : 'items'}
            </p>
          </div>

          <div className="cart-items">
            {cart.length === 0 ? (
              <div className="empty-cart">
                <Package size={48} style={{ opacity: 0.5, marginBottom: '12px' }} />
                <p>Click items to add to cart</p>
              </div>
            ) : (
              <div className="cart-items-list">
                {cart.map((item, index) => (
                  <div key={index} className="cart-item">
                    <div className="cart-item-icon">
                      <img 
                        src={`nui://ox_inventory/web/images/${item.item}.png`}
                        alt={item.label}
                        onError={(e) => {
                          e.target.style.display = 'none';
                          e.target.nextSibling.style.display = 'block';
                        }}
                      />
                      <div className="item-icon-fallback" style={{ display: 'none' }}><Package2 /></div>
                    </div>
                    <div className="cart-item-info">
                      <div className="cart-item-name">{item.label}</div>
                      <div className="cart-item-price">
                        {item.currency && item.currency !== 'cash' && item.currency !== 'bank'
                          ? `${item.price} × ${item.quantity}`
                          : `$${item.price} × ${item.quantity}`
                        }
                      </div>
                    </div>
                    <div className="cart-item-controls">
                      <button
                        onClick={() => updateQuantity(item.item, -1)}
                        className="quantity-button"
                      >
                        −
                      </button>
                      <span className="quantity-display">{item.quantity}</span>
                      <button
                        onClick={() => updateQuantity(item.item, 1)}
                        className="quantity-button"
                      >
                        +
                      </button>
                      <button
                        onClick={() => removeFromCart(item.item)}
                        className="delete-button"
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="cart-footer">
            <div className="cart-summary">
              <div className="summary-row total">
                <span className="summary-label-total">Total</span>
                <span className="summary-value-total">
                  {cart.length > 0 && cart[0].currency && cart[0].currency !== 'cash' && cart[0].currency !== 'bank'
                    ? `${getTotalPrice()} ${cart[0].currencyInfo?.label || cart[0].currency}`
                    : `$${getTotalPrice()}`
                  }
                </span>
              </div>
            </div>
            <button
              onClick={handleCheckout}
              className={`checkout-button ${cart.length === 0 ? 'disabled' : ''}`}
              disabled={cart.length === 0}
            >
              <ShoppingCart size={16} />
              Checkout
            </button>
          </div>
        </div>
      </div>

      {notification.show && (
        <div className={`notification ${notification.type}`}>
          {notification.message}
        </div>
      )}

      {showCheckoutModal && (
        <div className="modal-overlay" onClick={() => setShowCheckoutModal(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h2 className="modal-title">Complete Purchase</h2>
              <button className="modal-close" onClick={() => setShowCheckoutModal(false)}>
                <X size={20} />
              </button>
            </div>
            
            <div className="modal-body">
              <div className="modal-total">
                <span>Total Amount</span>
                <span className="modal-total-price">
                  {cart.length > 0 && cart[0].currency && cart[0].currency !== 'cash' && cart[0].currency !== 'bank'
                    ? `${getTotalPrice()} ${cart[0].currencyInfo?.label || cart[0].currency}`
                    : `$${getTotalPrice()}`
                  }
                </span>
              </div>
              
              <p className="modal-subtitle">Select Payment Method</p>
              
              <div className="payment-methods">
                {cart.length > 0 && cart[0].currency && cart[0].currency !== 'cash' && cart[0].currency !== 'bank' ? (
                  <button 
                    className="payment-button cash full-width"
                    onClick={() => completePurchase(cart[0].currency)}
                    disabled={!customCurrencies[cart[0].currency] || customCurrencies[cart[0].currency].count < getTotalPrice()}
                  >
                    <Wallet size={32} />
                    <span>{customCurrencies[cart[0].currency]?.label || cart[0].currency}</span>
                    <span className="payment-balance">{customCurrencies[cart[0].currency]?.count || 0}</span>
                  </button>
                ) : (
                  <>
                    <button 
                      className="payment-button card"
                      onClick={() => completePurchase('bank')}
                      disabled={playerMoney.bank < getTotalPrice()}
                    >
                      <CreditCard size={32} />
                      <span>Bank</span>
                      <span className="payment-balance">${playerMoney.bank}</span>
                    </button>
                    
                    <button 
                      className="payment-button cash"
                      onClick={() => completePurchase('cash')}
                      disabled={playerMoney.cash < getTotalPrice()}
                    >
                      <Wallet size={32} />
                      <span>Cash</span>
                      <span className="payment-balance">${playerMoney.cash}</span>
                    </button>
                  </>
                )}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

function GetParentResourceName() {
  return window.location.hostname === 'nui-game' ? window.GetParentResourceName() : 'LNS_Shops';
}

export default App;