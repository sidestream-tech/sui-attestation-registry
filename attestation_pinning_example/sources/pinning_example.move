module attestation_pinning_example::pinning_example;

use sui::package::{Self};

/// OTW to claim publisher
public struct PINNING_EXAMPLE has drop {}

/// Initilise the module by claiming publisher object
fun init(otw: PINNING_EXAMPLE, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);
    transfer::public_transfer(publisher, ctx.sender());
}

#[test_only]
/// Wrapper of module initializer for testing
public fun test_init(ctx: &mut TxContext) {
    init(PINNING_EXAMPLE {}, ctx)
}
