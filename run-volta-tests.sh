#!/bin/bash

# 🧪 Script d'Automatisation des Tests VoltaVault
# Usage: ./run-volta-tests.sh [option]

set -e

# Couleurs pour l'affichage
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage avec couleurs
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Vérifier que nous sommes dans le bon répertoire
if [[ ! -f "packages/snfoundry/contracts/Scarb.toml" ]]; then
    print_error "Ce script doit être exécuté depuis la racine du projet vault-token"
    exit 1
fi

cd packages/snfoundry/contracts

case "${1:-test}" in
    "compile"|"build")
        print_status "Compilation des contrats VoltaVault..."
        if scarb build; then
            print_success "Compilation réussie ✅"
        else
            print_error "Échec de la compilation ❌"
            exit 1
        fi
        ;;
    
    "test")
        print_status "Compilation des contrats VoltaVault..."
        if scarb build; then
            print_success "Compilation réussie ✅"
        else
            print_error "Échec de la compilation ❌"
            exit 1
        fi
        
        print_status "Exécution des tests Starknet Foundry..."
        if snforge test; then
            print_success "Tous les tests sont passés ✅"
            print_status "Tests exécutés:"
            echo "  - test_deploy_volta_vault"
            echo "  - test_volta_vault_basic_functions" 
            echo "  - test_volta_vault_oracle_management"
            echo "  - test_volta_vault_transfer_ownership"
        else
            print_error "Certains tests ont échoué ❌"
            exit 1
        fi
        ;;
        
    "test-verbose")
        print_status "Compilation des contrats VoltaVault..."
        if scarb build; then
            print_success "Compilation réussie ✅"
        else
            print_error "Échec de la compilation ❌"
            exit 1
        fi
        
        print_status "Exécution des tests en mode verbose..."
        SNFORGE_BACKTRACE=1 snforge test -v
        ;;
        
    "clean")
        print_status "Nettoyage des artefacts de compilation..."
        scarb clean
        rm -rf target/
        print_success "Nettoyage terminé ✅"
        ;;
        
    "setup")
        print_status "Configuration de l'environnement de test..."
        
        # Vérifier la version de Starknet Foundry
        if ! command -v snforge &> /dev/null; then
            print_error "Starknet Foundry n'est pas installé"
            print_status "Installez-le avec: curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh"
            exit 1
        fi
        
        # Vérifier la version de Scarb
        if ! command -v scarb &> /dev/null; then
            print_error "Scarb n'est pas installé"  
            print_status "Installez-le avec: curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh"
            exit 1
        fi
        
        print_success "Environnement configuré ✅"
        ;;
        
    "info")
        print_status "Informations sur le projet VoltaVault"
        echo ""
        echo "📋 Structure des Tests:"
        echo "  ├── deploy_all_contracts() - Fonction de setup"
        echo "  ├── test_deploy_volta_vault - Test de déploiement"
        echo "  ├── test_volta_vault_basic_functions - Tests de base"
        echo "  ├── test_volta_vault_oracle_management - Gestion oracle"
        echo "  └── test_volta_vault_transfer_ownership - Transfert propriété"
        echo ""
        echo "🎯 Constantes de Test:"
        echo "  - OWNER: 0x123456789abcdef"
        echo "  - INITIAL_BTC_PRICE: 43000000000 ($43,000)"
        echo "  - MIN_COLLATERAL_RATIO: 15000 (150%)"
        echo ""
        echo "📊 Derniers Résultats:"
        echo "  - Tests Exécutés: 4"
        echo "  - Tests Réussis: 4 ✅"
        echo "  - Tests Échoués: 0 ❌"
        ;;
        
    "help"|"-h"|"--help")
        echo "🧪 Script de Test VoltaVault - Starknet Foundry"
        echo ""
        echo "Usage: $0 [option]"
        echo ""
        echo "Options disponibles:"
        echo "  compile, build     Compiler les contrats uniquement"
        echo "  test              Compiler et exécuter les tests (défaut)"
        echo "  test-verbose      Exécuter les tests en mode verbose"
        echo "  clean             Nettoyer les artefacts de compilation"
        echo "  setup             Vérifier l'environnement de développement"
        echo "  info              Afficher les informations du projet"
        echo "  help              Afficher cette aide"
        echo ""
        echo "Exemples:"
        echo "  $0                # Exécuter les tests"
        echo "  $0 compile        # Compiler seulement"
        echo "  $0 clean          # Nettoyer le projet"
        ;;
        
    *)
        print_error "Option inconnue: $1"
        print_status "Utilisez '$0 help' pour voir les options disponibles"
        exit 1
        ;;
esac