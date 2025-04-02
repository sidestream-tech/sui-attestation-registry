module attestation_type_example::example;

use sui::package::{Self, Publisher};
use std::ascii::{String};
use attestation::attestation::{Self, Registry};

/// Attestation type
public struct ExampleAttestion has key, store {
    id: UID,
    what: String,
}

/// OTW to claim publisher
public struct EXAMPLE has drop {}

/// Initilise the module by claiming publisher object
fun init(otw: EXAMPLE, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);
    transfer::public_transfer(publisher, ctx.sender());
}

/// Create attestation type and its Display
public fun register_itself(
    publisher: &Publisher,
    registry: &mut Registry,
    ctx: &mut TxContext,
) {
    let is_revocable = true;
    let fields = vector[
        b"name".to_string(),
        b"description".to_string(),
        b"link".to_string(),
    ];
    let values = vector[
        b"Attestation Type Example".to_string(),
        b"Test usage of the Attesation package".to_string(),
        b"https://example.com/attestation/{id}".to_string(),
    ];
    attestation::register_type<ExampleAttestion>(registry, publisher, is_revocable, fields, values, ctx)
}

/// Create attestation
public fun attest(
    to: address,
    what: String,
    registry: &mut Registry,
    ctx: &mut TxContext,
) {
    let attestation_object = ExampleAttestion {
        id: object::new(ctx),
        what,
    };
    attestation::attest<ExampleAttestion>(
        registry,
        to,
        attestation_object,
        ctx,
    )
}
