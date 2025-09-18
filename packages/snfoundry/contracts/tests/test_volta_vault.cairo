use starknet::{ContractAddress, contract_address_const};
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address
};

// Import de l'interface VoltaVault
use contracts::VoltaVault::{IVoltaVaultDispatcher, IVoltaVaultDispatcherTrait};

// Constantes pour les tests
const OWNER: felt252 = 0x123456789abcdef; // Propriétaire des contrats
const INITIAL_BTC_PRICE: u256 = 43000000000; // $43,000 avec 6 décimales (43000 * 10^6)
const MIN_COLLATERAL_RATIO: u256 = 15000; // 150% (15000 / 10000 = 1.5)
const ORACLE_ADDRESS_NULL: felt252 = 0x0; // Adresse oracle nulle pour les tests
const SBTC_ADDRESS_MOCK: felt252 = 0x1111; // Adresse mock pour sBTC
const VUSD_ADDRESS_MOCK: felt252 = 0x2222; // Adresse mock pour vUSD

// Structure pour retourner les adresses des contrats déployés
#[derive(Drop, Copy)]
struct DeployedContracts {
    sbtc: ContractAddress,
    vusd: ContractAddress,
    volta_vault: ContractAddress,
}

/// Fonction de setup simplifiée - déploie uniquement VoltaVault avec des adresses mock
/// 
/// Cette version déploie uniquement VoltaVault pour tester sa logique interne
/// Les tokens sBTC et vUSD sont simulés par des adresses mock
/// 
/// Retourne:
/// - DeployedContracts: Structure contenant les adresses (mock pour sBTC et vUSD, vraie pour VoltaVault)
fn deploy_all_contracts() -> DeployedContracts {
    // Convertir les adresses en ContractAddress
    let owner_address = contract_address_const::<OWNER>();
    let oracle_address = contract_address_const::<ORACLE_ADDRESS_NULL>();
    let sbtc_mock_address = contract_address_const::<SBTC_ADDRESS_MOCK>();
    let vusd_mock_address = contract_address_const::<VUSD_ADDRESS_MOCK>();

    // Déployer uniquement le contrat VoltaVault avec des adresses mock
    let volta_vault_class = declare("VoltaVault").unwrap().contract_class();
    let volta_vault_constructor_calldata = array![
        sbtc_mock_address.into(), // sbtc_address (mock)
        vusd_mock_address.into(), // vusd_address (mock)
        oracle_address.into(), // pragma_oracle_address
        INITIAL_BTC_PRICE.low.into(), // initial_btc_price (low part)
        INITIAL_BTC_PRICE.high.into(), // initial_btc_price (high part)
        MIN_COLLATERAL_RATIO.low.into(), // min_collateral_ratio (low part)
        MIN_COLLATERAL_RATIO.high.into(), // min_collateral_ratio (high part)
        owner_address.into(), // owner
    ];
    let (volta_vault_address, _) = volta_vault_class.deploy(@volta_vault_constructor_calldata).unwrap();

    // Retourner les adresses des contrats (mock pour les tokens, vraie pour VoltaVault)
    DeployedContracts {
        sbtc: sbtc_mock_address,
        vusd: vusd_mock_address,
        volta_vault: volta_vault_address,
    }
}

#[cfg(test)]
mod tests {
    use super::{deploy_all_contracts, OWNER, INITIAL_BTC_PRICE};
    use starknet::contract_address_const;
    use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
    use contracts::VoltaVault::{IVoltaVaultDispatcher, IVoltaVaultDispatcherTrait};

    #[test]
    fn test_deploy_volta_vault() {
        // Déployer VoltaVault
        let contracts = deploy_all_contracts();
        
        // Vérifier que l'adresse du VoltaVault n'est pas nulle
        assert(contracts.volta_vault.into() != 0, 'VoltaVault deployment failed');
        
        // Vérifier que le VoltaVault a été configuré correctement
        let volta_vault = IVoltaVaultDispatcher { contract_address: contracts.volta_vault };
        
        // Vérifier le propriétaire
        let owner = volta_vault.get_owner();
        let expected_owner = contract_address_const::<OWNER>();
        assert(owner == expected_owner, 'Wrong owner');
        
        // NOTE: Ne pas tester get_btc_price() car il fait appel à l'oracle avec adresse nulle
    }

    #[test]
    fn test_volta_vault_basic_functions() {
        let contracts = deploy_all_contracts();
        let volta_vault = IVoltaVaultDispatcher { contract_address: contracts.volta_vault };
        let owner_address = contract_address_const::<OWNER>();
        let user_address = contract_address_const::<0x5555>();
        
        // Test des fonctions qui ne font pas appel à l'oracle
        let user_collateral = volta_vault.get_user_collateral(user_address);
        assert(user_collateral == 0, 'Initial collateral should be 0');
        
        let user_debt = volta_vault.get_user_debt(user_address);
        assert(user_debt == 0, 'Initial debt should be 0');
        
        let user_ratio = volta_vault.get_collateral_ratio(user_address);
        assert(user_ratio == 0, 'Initial ratio should be 0');
    }

    #[test]
    fn test_volta_vault_oracle_management() {
        let contracts = deploy_all_contracts();
        let volta_vault = IVoltaVaultDispatcher { contract_address: contracts.volta_vault };
        let owner_address = contract_address_const::<OWNER>();
        
        // Test de désactivation de l'oracle (ne devrait pas faire d'appels)
        start_cheat_caller_address(contracts.volta_vault, owner_address);
        volta_vault.set_oracle_usage(false); // Désactiver l'oracle
        stop_cheat_caller_address(contracts.volta_vault);
        
        // Maintenant on peut tester get_btc_price car l'oracle est désactivé
        start_cheat_caller_address(contracts.volta_vault, owner_address);
        let new_price: u256 = 45000000000; // $45,000
        volta_vault.update_btc_price(new_price);
        
        let updated_price = volta_vault.get_btc_price();
        assert(updated_price == new_price, 'BTC price update failed');
        stop_cheat_caller_address(contracts.volta_vault);
    }

    #[test]
    fn test_volta_vault_transfer_ownership() {
        let contracts = deploy_all_contracts();
        let volta_vault = IVoltaVaultDispatcher { contract_address: contracts.volta_vault };
        let owner_address = contract_address_const::<OWNER>();
        let new_owner_address = contract_address_const::<0x9999>();
        
        // Transférer la propriété
        start_cheat_caller_address(contracts.volta_vault, owner_address);
        volta_vault.transfer_ownership(new_owner_address);
        stop_cheat_caller_address(contracts.volta_vault);
        
        // Vérifier que la propriété a été transférée
        let current_owner = volta_vault.get_owner();
        assert(current_owner == new_owner_address, 'Ownership transfer failed');
    }
}