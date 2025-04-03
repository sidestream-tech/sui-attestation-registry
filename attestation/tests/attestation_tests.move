#[test_only]
module attestation::attestation_tests;

/// Imports
use sui::test_scenario;
use sui::package::{Self, Publisher};
use attestation::attestation::{Self, Registry, Attestation, AttestationType};

/// Test attestation type
public struct TestAttestion has key, store {
    id: UID,
    is_good: bool,
}

/// OTW to claim publisher
public struct ATTESTATION_TESTS has drop {}

/// Initilise the module by claiming publisher object
fun init(otw: ATTESTATION_TESTS, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);
    transfer::public_transfer(publisher, ctx.sender());
}

#[test]
fun test_happy_path() {
    let package_creator = @0xA11CE;
    let type_creator = @0xB0B;
    let attestation_creator = @0xCAFE;
    let attestation_receiver = @0xFACE;

    let mut scenario = test_scenario::begin(package_creator);
    // Publish attestation package
    {
        attestation::test_init(test_scenario::ctx(&mut scenario));
    };

    scenario.next_tx(type_creator);
    // Publish type package
    {
        init(ATTESTATION_TESTS {}, test_scenario::ctx(&mut scenario));
    };

    scenario.next_tx(attestation_creator);
    // Register new type
    {
        // Borrow required objects
        let mut package_registry = test_scenario::take_shared<Registry>(&scenario);
        let type_publisher = test_scenario::take_from_address<Publisher>(&scenario, type_creator);

        // Try to create type
        attestation::register_type<TestAttestion>(
            &type_publisher,
            true,
            vector[],
            vector[],
            &mut package_registry,
            test_scenario::ctx(&mut scenario)
        );

        // Return borrowed
        test_scenario::return_shared(package_registry);
        test_scenario::return_to_address<Publisher>(type_creator, type_publisher);
    };

    scenario.next_tx(attestation_creator);
    // Create new attestation
    {
        // Borrow required objects
        let attestation_type = test_scenario::take_immutable<AttestationType>(&scenario);
        
        attestation::attest<TestAttestion>(
            TestAttestion {
                id: object::new(test_scenario::ctx(&mut scenario)),
                is_good: true
            },
            attestation_receiver,
            &attestation_type,
            test_scenario::ctx(&mut scenario),
        );

        // Return borrowed
        test_scenario::return_immutable(attestation_type);
    };

    scenario.next_tx(attestation_creator);
    // Revoke previously created attestation
    {
        // Borrow required objects
        let attestation_type = test_scenario::take_immutable<AttestationType>(&scenario);
        let attestation = test_scenario::take_from_address<Attestation<TestAttestion>>(&scenario, attestation_receiver);

        attestation::revoke<TestAttestion>(
            &attestation,
            &attestation_type,
            test_scenario::ctx(&mut scenario),
        );

        // Return borrowed
        test_scenario::return_immutable(attestation_type);
        test_scenario::return_to_address<Attestation<TestAttestion>>(attestation_receiver, attestation);
    };

    scenario.end();
}
