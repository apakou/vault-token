use starknet::ContractAddress;

#[starknet::interface]
pub trait IVoltaVault<TContractState> {
    fn deposit_and_mint(ref self: TContractState, collateral_amount: u256, mint_amount: u256);
    fn withdraw_and_burn(ref self: TContractState, withdraw_amount: u256, burn_amount: u256);
    fn get_user_collateral(self: @TContractState, user: ContractAddress) -> u256;
    fn get_user_debt(self: @TContractState, user: ContractAddress) -> u256;
    fn get_collateral_ratio(self: @TContractState, user: ContractAddress) -> u256;
    fn update_btc_price(ref self: TContractState, new_price: u256);
    fn get_btc_price(self: @TContractState) -> u256;
    fn set_oracle_usage(ref self: TContractState, use_oracle: bool);
    fn update_oracle_address(ref self: TContractState, new_oracle_address: ContractAddress);
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
    fn diagnose_oracle(self: @TContractState) -> (bool, u256, bool);
}

#[starknet::contract]
mod VoltaVault {
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    // Interface Pragma Oracle (simplifiée pour le MVP)
    #[starknet::interface]
    trait IPragmaOracle<TContractState> {
        fn get_data_median(self: @TContractState, pair_id: felt252) -> (u128, u32, u32, u32);
    }

    // Interface pour les contrats personnalisés avec mint/burn
    #[starknet::interface]
    trait ITokenWithMint<TContractState> {
        fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
        fn burn(ref self: TContractState, account: ContractAddress, amount: u256);
    }

    #[storage]
    struct Storage {
        // Adresses des contrats de tokens
        sbtc_token: ContractAddress,
        vusd_token: ContractAddress,
        
        // Mappings pour suivre les positions des utilisateurs
        // user_address => collateral_balance (montant de sBTC déposé)
        collateral_balances: Map<ContractAddress, u256>,
        
        // user_address => debt_balance (montant de vUSD emprunté)
        debt_balances: Map<ContractAddress, u256>,
        
        // Ratio de collatéralisation minimum (en pourcentage * 100, ex: 15000 = 150%)
        min_collateral_ratio: u256,
        
        // Oracle Pragma
        pragma_oracle_address: ContractAddress,
        use_oracle: bool,
        
        // Prix du Bitcoin en USD (fallback quand oracle indisponible)
        fallback_btc_price: u256,
        
        // Propriétaire du contrat
        owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CollateralDeposited: CollateralDeposited,
        StablecoinMinted: StablecoinMinted,
        CollateralWithdrawn: CollateralWithdrawn,
        StablecoinBurned: StablecoinBurned,
        PriceUpdateFailed: PriceUpdateFailed,
        OracleToggled: OracleToggled,
        OwnershipTransferred: OwnershipTransferred,
    }

    #[derive(Drop, starknet::Event)]
    struct CollateralDeposited {
        #[key]
        user: ContractAddress,
        amount: u256,
        new_collateral_balance: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct StablecoinMinted {
        #[key]
        user: ContractAddress,
        amount: u256,
        new_debt_balance: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct CollateralWithdrawn {
        #[key]
        user: ContractAddress,
        amount: u256,
        new_collateral_balance: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct StablecoinBurned {
        #[key]
        user: ContractAddress,
        amount: u256,
        new_debt_balance: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PriceUpdateFailed {
        error: felt252,
        fallback_price_used: u256,
    }

    #[derive(Drop, starknet::Event)]  
    struct OracleToggled {
        enabled: bool,
        oracle_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        #[key]
        previous_owner: ContractAddress,
        #[key]
        new_owner: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        sbtc_address: ContractAddress,
        vusd_address: ContractAddress,
        pragma_oracle_address: ContractAddress,
        initial_btc_price: u256,
        min_collateral_ratio: u256,
        owner: ContractAddress
    ) {
        // Initialiser les adresses des contrats de tokens
        self.sbtc_token.write(sbtc_address);
        self.vusd_token.write(vusd_address);
        
        // Initialiser l'oracle Pragma
        self.pragma_oracle_address.write(pragma_oracle_address);
        self.use_oracle.write(true);
        
        // Initialiser le prix BTC fallback
        self.fallback_btc_price.write(initial_btc_price);
        
        // Ratio de collatéralisation minimum (ex: 15000 = 150%)
        self.min_collateral_ratio.write(min_collateral_ratio);
        
        // Initialiser le propriétaire
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl VoltaVaultImpl of super::IVoltaVault<ContractState> {
        /// Déposer du collatéral (sBTC) et minter des stablecoins (vUSD)
        fn deposit_and_mint(ref self: ContractState, collateral_amount: u256, mint_amount: u256) {
            let caller = get_caller_address();
            let vault_address = starknet::get_contract_address();
            
            assert(collateral_amount > 0, 'Collateral amount must be > 0');
            assert(mint_amount > 0, 'Mint amount must be > 0');
            
            // Transférer le collatéral sBTC du user vers le vault
            let sbtc_token = IERC20Dispatcher { contract_address: self.sbtc_token.read() };
            sbtc_token.transfer_from(
                caller, 
                vault_address, 
                collateral_amount
            );
            
            // Mettre à jour le solde de collatéral de l'utilisateur
            let current_collateral = self.collateral_balances.read(caller);
            let new_collateral = current_collateral + collateral_amount;
            self.collateral_balances.write(caller, new_collateral);
            
            // Calculer la valeur du collatéral en USD
            let btc_price = self._get_btc_price();
            let _collateral_value_usd = collateral_amount * btc_price / 100000000; // Division par 10^8 (8 décimales BTC)
            
            // Vérifier le ratio de collatéralisation
            let current_debt = self.debt_balances.read(caller);
            let new_debt = current_debt + mint_amount;
            let min_ratio = self.min_collateral_ratio.read(); // ex: 15000 = 150%
            let required_collateral = new_debt * min_ratio / 10000; // Division par 10000 pour convertir le pourcentage
            
            // Calculer la valeur totale du collatéral (existant + nouveau)
            let total_collateral = self.collateral_balances.read(caller) + collateral_amount;
            let total_collateral_value = total_collateral * btc_price / 100000000;
            
            assert(total_collateral_value >= required_collateral, 'Insufficient collateral');
            
            // Mettre à jour la dette de l'utilisateur
            if mint_amount > 0 {
                let current_debt = self.debt_balances.read(caller);
                let new_debt = current_debt + mint_amount;
                self.debt_balances.write(caller, new_debt);
                
                // Minter les vUSD vers l'utilisateur
                let vusd_token = ITokenWithMintDispatcher { contract_address: self.vusd_token.read() };
                vusd_token.mint(caller, mint_amount);
                
                self.emit(StablecoinMinted { 
                    user: caller, 
                    amount: mint_amount, 
                    new_debt_balance: new_debt 
                });
            }
            
            self.emit(CollateralDeposited { 
                user: caller, 
                amount: collateral_amount, 
                new_collateral_balance: new_collateral 
            });
        }

        /// Retirer du collatéral et brûler des stablecoins
        fn withdraw_and_burn(ref self: ContractState, withdraw_amount: u256, burn_amount: u256) {
            let caller = get_caller_address();
            
            // 1. Vérifier que l'utilisateur a suffisamment de collatéral et de dette
            let current_collateral = self.collateral_balances.read(caller);
            let current_debt = self.debt_balances.read(caller);
            
            assert(withdraw_amount <= current_collateral, 'Insufficient collateral balance');
            assert(burn_amount <= current_debt, 'Insufficient debt balance');
            
            // 2. Brûler les vUSD d'abord (l'utilisateur doit avoir approuvé le vault)
            if burn_amount > 0 {
                let vusd_token = IERC20Dispatcher { contract_address: self.vusd_token.read() };
                vusd_token.transfer_from(caller, starknet::get_contract_address(), burn_amount);
                
                // Appeler la fonction burn du contrat vUSD
                let vusd_mint_token = ITokenWithMintDispatcher { contract_address: self.vusd_token.read() };
                vusd_mint_token.burn(starknet::get_contract_address(), burn_amount);
                
                // Mettre à jour la dette
                let new_debt = current_debt - burn_amount;
                self.debt_balances.write(caller, new_debt);
                
                self.emit(StablecoinBurned { 
                    user: caller, 
                    amount: burn_amount, 
                    new_debt_balance: new_debt 
                });
            }
            
            // 3. Vérifier que le ratio de collatéralisation reste valide après retrait
            if withdraw_amount > 0 {
                let new_collateral = current_collateral - withdraw_amount;
                let remaining_debt = current_debt - burn_amount;
                
                // Si il reste de la dette, vérifier le ratio
                if remaining_debt > 0 {
                    let btc_price = self._get_btc_price();
                    let remaining_collateral_value = new_collateral * btc_price / 100000000;
                    let min_ratio = self.min_collateral_ratio.read();
                    let required_collateral = remaining_debt * min_ratio / 10000;
                    
                    assert(remaining_collateral_value >= required_collateral, 'Would breach collateral ratio');
                }
                
                // 4. Transférer le collatéral vers l'utilisateur
                let sbtc_token = IERC20Dispatcher { contract_address: self.sbtc_token.read() };
                sbtc_token.transfer(caller, withdraw_amount);
                
                // Mettre à jour le solde de collatéral
                self.collateral_balances.write(caller, new_collateral);
                
                self.emit(CollateralWithdrawn { 
                    user: caller, 
                    amount: withdraw_amount, 
                    new_collateral_balance: new_collateral 
                });
            }
        }

        /// Récupérer le solde de collatéral d'un utilisateur
        fn get_user_collateral(self: @ContractState, user: ContractAddress) -> u256 {
            self.collateral_balances.read(user)
        }

        /// Récupérer la dette d'un utilisateur
        fn get_user_debt(self: @ContractState, user: ContractAddress) -> u256 {
            self.debt_balances.read(user)
        }

        /// Calculer le ratio de collatéralisation d'un utilisateur
        fn get_collateral_ratio(self: @ContractState, user: ContractAddress) -> u256 {
            let collateral_balance = self.collateral_balances.read(user);
            let debt_balance = self.debt_balances.read(user);
            
            if debt_balance == 0 {
                return 0; // Pas de dette = pas de ratio significatif
            }
            
            // Utiliser le prix réel du BTC depuis un oracle (pour le MVP, on utilise le prix stocké)
            let btc_price = self._get_btc_price();
            
            // Calculer: (collateral_value_usd * 10000) / debt_balance
            let collateral_value_usd = collateral_balance * btc_price / 100000000; // Division par 10^8 pour les décimales BTC
            let ratio = (collateral_value_usd * 10000) / debt_balance; // Ratio en pourcentage * 100 (ex: 15000 = 150%)
            
            ratio
        }

        /// Mettre à jour le prix du Bitcoin fallback (réservé au propriétaire)
        fn update_btc_price(ref self: ContractState, new_price: u256) {
            self._assert_only_owner();
            self.fallback_btc_price.write(new_price);
        }

        /// Récupérer le prix actuel du Bitcoin
        fn get_btc_price(self: @ContractState) -> u256 {
            self._get_btc_price()
        }

        /// Activer/désactiver l'oracle Pragma (réservé au propriétaire)
        fn set_oracle_usage(ref self: ContractState, use_oracle: bool) {
            self._assert_only_owner();
            let oracle_address = self.pragma_oracle_address.read();
            self.use_oracle.write(use_oracle);
            
            self.emit(OracleToggled { 
                enabled: use_oracle, 
                oracle_address 
            });
        }
        
        /// Mettre à jour l'adresse de l'oracle Pragma (réservé au propriétaire)
        fn update_oracle_address(ref self: ContractState, new_oracle_address: ContractAddress) {
            self._assert_only_owner();
            self.pragma_oracle_address.write(new_oracle_address);
            
            self.emit(OracleToggled { 
                enabled: self.use_oracle.read(), 
                oracle_address: new_oracle_address 
            });
        }

        /// Récupérer le propriétaire du contrat
        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        /// Transférer la propriété du contrat
        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            self._assert_only_owner();
            let previous_owner = self.owner.read();
            self.owner.write(new_owner);
            
            self.emit(OwnershipTransferred { 
                previous_owner, 
                new_owner 
            });
        }

        /// Diagnostiquer l'état de l'oracle (oracle_enabled, current_price, oracle_working)
        fn diagnose_oracle(self: @ContractState) -> (bool, u256, bool) {
            let oracle_enabled = self.use_oracle.read();
            let current_price = self._get_btc_price();
            let oracle_working = if oracle_enabled {
                match self._get_pragma_btc_price() {
                    Option::Some(price) => price > 0,
                    Option::None => false
                }
            } else {
                false
            };
            
            (oracle_enabled, current_price, oracle_working)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Vérifier que seul le propriétaire peut exécuter cette fonction
        fn _assert_only_owner(self: @ContractState) {
            let caller = starknet::get_caller_address();
            let owner = self.owner.read();
            assert!(caller == owner, "Caller is not the owner");
        }

        /// Fonction interne pour obtenir le prix BTC via Pragma Oracle avec fallback
        fn _get_btc_price(self: @ContractState) -> u256 {
            let use_oracle = self.use_oracle.read();
            
            if use_oracle {
                // Essayer d'obtenir le prix via Pragma Oracle
                match self._get_pragma_btc_price() {
                    Option::Some(price) => {
                        // Vérifier que le prix est raisonnable (pas 0)
                        if price > 0 {
                            return price;
                        }
                    },
                    Option::None => {
                        // En cas d'erreur, utiliser le fallback (on ne peut pas émettre d'événement ici)
                        // L'événement sera émis par une fonction publique si nécessaire
                    }
                }
            }
            
            // Fallback : utiliser le prix manuel
            self.fallback_btc_price.read()
        }
        
        /// Interroger l'oracle Pragma pour le prix BTC/USD
        fn _get_pragma_btc_price(self: @ContractState) -> Option<u256> {
            let oracle_address = self.pragma_oracle_address.read();
            let oracle = IPragmaOracleDispatcher { contract_address: oracle_address };
            
            // BTC/USD pair ID pour Pragma (simplifié)
            let btc_usd_pair_id = 'BTC/USD';
            
            // Appeler l'oracle avec gestion d'erreur basique
            // Pour simplifier, on retourne None en cas d'erreur
            // Dans une vraie implémentation, on gérerait les exceptions
            let (price, _decimals, _last_updated, _num_sources) = oracle.get_data_median(btc_usd_pair_id);
            
            if price > 0 {
                Option::Some(price.into())
            } else {
                Option::None
            }
        }
        
        /// Fonction interne pour valider le ratio de collatéralisation
        fn _validate_collateral_ratio(
            self: @ContractState, 
            user: ContractAddress, 
            collateral_amount: u256, 
            debt_amount: u256
        ) -> bool {
            // Calculer la valeur du collatéral en USD
            let collateral_value = self._get_collateral_value_usd(collateral_amount);
            
            // Vérifier que collateral_value >= debt * min_collateral_ratio
            let min_ratio = self.min_collateral_ratio.read();
            let required_collateral = debt_amount * min_ratio / 10000;
            
            collateral_value >= required_collateral
        }
        
        /// Fonction interne pour calculer la valeur du collatéral en USD
        fn _get_collateral_value_usd(self: @ContractState, collateral_amount: u256) -> u256 {
            // Utiliser la fonction _get_btc_price pour obtenir le prix (avec oracle)
            let btc_price = self._get_btc_price();
            
            // Calculer la valeur : collateral_amount * prix_btc / 10^8 (8 décimales pour BTC)
            collateral_amount * btc_price / 100000000
        }
    }
}
