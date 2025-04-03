#[test_only]
module attestation_type_example::example_tests;

/// Imports
use sui::test_scenario;
use std::ascii;
use sui::package::{Publisher};
use attestation::attestation::{Self, Registry, AttestationType};
use attestation_type_example::example::{Self};

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
        example::test_init(test_scenario::ctx(&mut scenario));
    };

    scenario.next_tx(type_creator);
    // Register itself
    {
        // Borrow required objects
        let type_publisher = test_scenario::take_from_address<Publisher>(&scenario, type_creator);
        let mut package_registry = test_scenario::take_shared<Registry>(&scenario);

        example::register_itself(&type_publisher, &mut package_registry, test_scenario::ctx(&mut scenario));

        test_scenario::return_shared(package_registry);
        test_scenario::return_to_address<Publisher>(type_creator, type_publisher);
    };

    scenario.next_tx(attestation_creator);
    // Attest
    {
        // Borrow required objects
        let attestation_type = test_scenario::take_immutable<AttestationType>(&scenario);

        // Try to create attestation
        example::attest(
            attestation_receiver,
            ascii::string(b"test"),
            &attestation_type,
            test_scenario::ctx(&mut scenario),
        );

        // Return borrowed
        test_scenario::return_immutable(attestation_type);
    };

    scenario.end();
}
