-module(lee_interface_module).

-callback model() -> lee:lee_module().

-callback metamodel() -> lee:lee_module().

-optional_callbacks([model/0, metamodel/0]).
