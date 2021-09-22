cc_library(
    name = "lean4",
    srcs = [
        "lib/lean/libleanrt.a",
        "lib/lean/libInit.a",
        "lib/lean/libStd.a",
        "lib/lean/libLean.a"
    ],
    hdrs = [
        "include/lean/lean.h",
        "include/lean/config.h",
        "include/lean/version.h",
        "include/lean/lean_gmp.h"
    ],
    visibility = ["//visibility:public"],
    strip_include_prefix = "include",
)