//! This module provides validation capabilities for data in bitfields. An
//! interface, `Validator`, is provided, along with a handful of example
//! implementations of the interface.
//!
//! Example:
//!
//! Using the `validators.Exact` implementation as a reference, usage looks
//! like the following:
//!
//! ```zig
//! const validator = Exact.init(u8, 0, .{});
//! // Verify that the value matches the rule by a void return rather than an error.
//! try validator.validate(0);
//!
//! // This will return an error because the rule of Exact requires an exact match.
//! try validator.validate(1);
//! ```

const std = @import("std");

/// The Validator interface provides a mechanism for field validation. Proper
/// instantiation should use the `init` function. See the provided set of
/// validation functions and their tests in `validators` for example
/// instantiation and usage.
pub const Validator = struct {
    /// Points to a concrete validation function.
    func_ptr: *const anyopaque,

    /// The type of value that will be provided to the validation function.
    type: type,

    /// Validate a value against the rules of the function that instantiated
    /// this `Validator`.
    pub fn validate(self: Validator, value: self.type) !void {
        const ValidatorFn = *const fn (self.type) anyerror!void;
        const func: ValidatorFn = @ptrCast(@alignCast(self.func_ptr));
        return func(value);
    }

    /// Initialize an instance of a `Validator` from a function. The function
    /// must take exactly one parameter, of the provided type.
    pub fn init(comptime func: anytype) Validator {
        const type_info = @typeInfo(@TypeOf(func));
        switch (type_info) {
            .@"fn" => |fn_info| {
                if (fn_info.params.len != 1) {
                    @compileError("validation function must take exactly 1 parameter");
                }
            },
            else => |t| {
                @compileError(
                    "validator init parameter must be a function, but provided type was " ++ @tagName(t),
                );
            },
        }

        const param_type = type_info.@"fn".params[0].type orelse @compileError(
            "parameter must be typed in order to create a validator",
        );

        return .{
            .type = param_type,
            .func_ptr = @ptrCast(&func),
        };
    }
};

/// This contains a set of common validation rules, which may be provided as
/// field validators. There are configuration options for each type if you
/// would like to customize behavior, however defaults are provided for
/// configuration for common cases.
pub const validators = struct {
    /// Validate that a value exactly matches an expected value. This is useful
    /// for cases such as padding or reserved bits, which are typically defined
    /// having specific values.
    pub const Exact = struct {
        /// Create an instance of the validator.
        pub fn init(
            comptime T: type,
            comptime expected: T,
            comptime cfg: Config,
        ) Validator {
            const Impl = struct {
                fn validate(value: T) !void {
                    if (value != expected) {
                        return cfg.err;
                    }
                }
            };
            return Validator.init(Impl.validate);
        }

        /// Configuration options for the validator.
        pub const Config = struct {
            /// The error to return when validation fails.
            err: anyerror = error.InvalidFieldValue,
        };

        test "unsigned integer with default config" {
            const validator = Exact.init(u8, 0, .{});
            try validator.validate(0);
            try std.testing.expectError(
                error.InvalidFieldValue,
                validator.validate(
                    1,
                ),
            );
        }

        test "unsigned integer with custom error" {
            const validator = Exact.init(
                u8,
                0,
                .{
                    .err = error.CustomError,
                },
            );
            try validator.validate(0);
            try std.testing.expectError(
                error.CustomError,
                validator.validate(
                    1,
                ),
            );
        }

        test "signed integer with default config" {
            const validator = Exact.init(i8, -1, .{});
            try validator.validate(-1);
            try std.testing.expectError(
                error.InvalidFieldValue,
                validator.validate(
                    1,
                ),
            );
        }

        test "signed integer with custom error" {
            const validator = Exact.init(i8, -1, .{
                .err = error.CustomError,
            });
            try validator.validate(-1);
            try std.testing.expectError(
                error.CustomError,
                validator.validate(
                    1,
                ),
            );
        }

        test "enum with default config" {
            const MyEnum = enum {
                a,
                b,
            };
            const validator = Exact.init(MyEnum, .a, .{});
            try validator.validate(.a);
            try std.testing.expectError(
                error.InvalidFieldValue,
                validator.validate(
                    .b,
                ),
            );
        }

        test "enum with custom error" {
            const MyEnum = enum {
                a,
                b,
            };
            const validator = Exact.init(
                MyEnum,
                .a,
                .{
                    .err = error.CustomError,
                },
            );
            try validator.validate(.a);
            try std.testing.expectError(
                error.CustomError,
                validator.validate(
                    .b,
                ),
            );
        }
    };

    /// Validate that a numeric value is greater than or equal to an expected
    /// value.
    pub const Min = struct {
        /// Create an instance of the validator.
        pub fn init(
            comptime T: type,
            comptime comparison: T,
            comptime cfg: Config,
        ) Validator {
            switch (@typeInfo(T)) {
                .int, .float => {},
                else => {
                    @compileError("min validator only supports numeric types");
                },
            }

            const Impl = struct {
                fn validate(value: T) !void {
                    if (value < comparison) {
                        return cfg.err;
                    }
                }
            };
            return Validator.init(Impl.validate);
        }

        /// Configuration options for the validator.
        pub const Config = struct {
            /// The error to return when validation fails.
            err: anyerror = error.ValueBelowMinimum,
        };

        test "unsigned integer with default config" {
            const validator = Min.init(u8, 42, .{});
            try validator.validate(42);
            try validator.validate(43);
            try std.testing.expectError(
                error.ValueBelowMinimum,
                validator.validate(
                    1,
                ),
            );
        }

        test "unsigned integer with custom error" {
            const validator = Min.init(
                u8,
                42,
                .{
                    .err = error.CustomError,
                },
            );
            try validator.validate(42);
            try validator.validate(43);
            try std.testing.expectError(
                error.CustomError,
                validator.validate(
                    1,
                ),
            );
        }

        test "signed integer with default config" {
            const validator = Min.init(i8, 0, .{});
            try validator.validate(0);
            try validator.validate(1);
            try std.testing.expectError(
                error.ValueBelowMinimum,
                validator.validate(
                    -1,
                ),
            );
        }

        test "signed integer with custom error" {
            const validator = Min.init(
                i8,
                0,
                .{
                    .err = error.CustomError,
                },
            );
            try validator.validate(0);
            try validator.validate(1);
            try std.testing.expectError(
                error.CustomError,
                validator.validate(
                    -1,
                ),
            );
        }

        test "float with default config" {
            const validator = Min.init(f64, 3.14, .{});
            try validator.validate(3.14);
            try validator.validate(3.1415);
            try std.testing.expectError(
                error.ValueBelowMinimum,
                validator.validate(
                    3.1,
                ),
            );
        }

        test "float with custom error" {
            const validator = Min.init(
                f64,
                3.14,
                .{
                    .err = error.CustomError,
                },
            );
            try validator.validate(3.14);
            try validator.validate(3.1415);
            try std.testing.expectError(
                error.CustomError,
                validator.validate(
                    3.1,
                ),
            );
        }
    };

    /// Validate that a numeric value is less than or equal to an expected
    /// value.
    pub const Max = struct {
        /// Create an instance of the validator.
        pub fn init(
            comptime T: type,
            comptime comparison: T,
            comptime cfg: Config,
        ) Validator {
            switch (@typeInfo(T)) {
                .int, .float => {},
                else => {
                    @compileError("max validator only supports numeric types");
                },
            }

            const Impl = struct {
                fn validate(value: T) !void {
                    if (value > comparison) {
                        return cfg.err;
                    }
                }
            };
            return Validator.init(Impl.validate);
        }

        /// Configuration options for the validator.
        pub const Config = struct {
            /// The error to return when validation fails.
            err: anyerror = error.ValueAboveMaximum,
        };

        test "unsigned integer with default config" {
            const validator = Max.init(u8, 42, .{});
            try validator.validate(42);
            try validator.validate(41);
            try std.testing.expectError(
                error.ValueAboveMaximum,
                validator.validate(
                    43,
                ),
            );
        }

        test "unsigned integer with custom error" {
            const validator = Max.init(
                u8,
                42,
                .{
                    .err = error.CustomError,
                },
            );
            try validator.validate(42);
            try validator.validate(41);
            try std.testing.expectError(
                error.CustomError,
                validator.validate(
                    43,
                ),
            );
        }

        test "signed integer with default config" {
            const validator = Max.init(i8, 0, .{});
            try validator.validate(0);
            try validator.validate(-1);
            try std.testing.expectError(
                error.ValueAboveMaximum,
                validator.validate(
                    1,
                ),
            );
        }

        test "signed integer with custom error" {
            const validator = Max.init(
                i8,
                0,
                .{
                    .err = error.CustomError,
                },
            );
            try validator.validate(0);
            try validator.validate(-1);
            try std.testing.expectError(
                error.CustomError,
                validator.validate(
                    1,
                ),
            );
        }

        test "float with default config" {
            const validator = Max.init(f64, 3.14, .{});
            try validator.validate(3.14);
            try validator.validate(3.1);
            try std.testing.expectError(
                error.ValueAboveMaximum,
                validator.validate(
                    3.1415,
                ),
            );
        }

        test "float with custom error" {
            const validator = Max.init(
                f64,
                3.14,
                .{
                    .err = error.CustomError,
                },
            );
            try validator.validate(3.14);
            try validator.validate(3.1);
            try std.testing.expectError(
                error.CustomError,
                validator.validate(
                    3.1415,
                ),
            );
        }
    };

    /// Validate that a numeric value is within a provided range (inclusive).
    pub const Range = struct {
        /// Create an instance of the validator.
        pub fn init(
            comptime T: type,
            comptime min_comparison: T,
            comptime max_comparison: T,
            comptime cfg: Config,
        ) Validator {
            switch (@typeInfo(T)) {
                .int, .float => {},
                else => {
                    @compileError("range validator only supports numeric types");
                },
            }

            const Impl = struct {
                fn validate(value: T) !void {
                    if (value < min_comparison) {
                        return cfg.min_err;
                    }
                    if (value > max_comparison) {
                        return cfg.max_err;
                    }
                }
            };
            return Validator.init(Impl.validate);
        }

        /// Configuration options for the validator.
        pub const Config = struct {
            /// The error to return when the value is below the minimum allowed.
            min_err: anyerror = error.ValueBelowMinimum,

            /// The error to return when the value is above the maximum allowed.
            max_err: anyerror = error.ValueAboveMaximum,
        };
    };

    test "unsigned integer with default config" {
        const validator = Range.init(
            u8,
            40,
            50,
            .{},
        );
        try validator.validate(40);
        try validator.validate(50);
        try validator.validate(45);
        try std.testing.expectError(
            error.ValueBelowMinimum,
            validator.validate(
                39,
            ),
        );
        try std.testing.expectError(
            error.ValueAboveMaximum,
            validator.validate(
                51,
            ),
        );
    }

    test "unsigned integer with custom errors" {
        const validator = Range.init(
            u8,
            40,
            50,
            .{
                .min_err = error.CustomMinimumError,
                .max_err = error.CustomMaximumError,
            },
        );
        try validator.validate(40);
        try validator.validate(50);
        try validator.validate(45);
        try std.testing.expectError(
            error.CustomMinimumError,
            validator.validate(
                39,
            ),
        );
        try std.testing.expectError(
            error.CustomMaximumError,
            validator.validate(
                51,
            ),
        );
    }

    test "signed integer with default config" {
        const validator = Range.init(
            i8,
            -1,
            1,
            .{},
        );
        try validator.validate(-1);
        try validator.validate(0);
        try validator.validate(1);
        try std.testing.expectError(
            error.ValueBelowMinimum,
            validator.validate(
                -2,
            ),
        );
        try std.testing.expectError(
            error.ValueAboveMaximum,
            validator.validate(
                2,
            ),
        );
    }

    test "signed integer with custom error" {
        const validator = Range.init(
            i8,
            -1,
            1,
            .{
                .min_err = error.CustomMinimumError,
                .max_err = error.CustomMaximumError,
            },
        );
        try validator.validate(-1);
        try validator.validate(0);
        try validator.validate(1);
        try std.testing.expectError(
            error.CustomMinimumError,
            validator.validate(
                -2,
            ),
        );
        try std.testing.expectError(
            error.CustomMaximumError,
            validator.validate(
                2,
            ),
        );
    }

    test "float with default config" {
        const validator = Range.init(
            f64,
            3.1,
            3.2,
            .{},
        );
        try validator.validate(3.1);
        try validator.validate(3.15);
        try validator.validate(3.2);
        try std.testing.expectError(
            error.ValueBelowMinimum,
            validator.validate(
                3,
            ),
        );
        try std.testing.expectError(
            error.ValueAboveMaximum,
            validator.validate(
                3.3,
            ),
        );
    }

    test "float with custom error" {
        const validator = Range.init(
            f64,
            3.1,
            3.2,
            .{
                .min_err = error.CustomMinimumError,
                .max_err = error.CustomMaximumError,
            },
        );
        try validator.validate(3.1);
        try validator.validate(3.15);
        try validator.validate(3.2);
        try std.testing.expectError(
            error.CustomMinimumError,
            validator.validate(
                3,
            ),
        );
        try std.testing.expectError(
            error.CustomMaximumError,
            validator.validate(
                3.3,
            ),
        );
    }

    test {
        std.testing.refAllDecls(@This());
    }
};

test {
    std.testing.refAllDecls(@This());
}
