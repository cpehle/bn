load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

http_archive(
    name = "lean4",
    urls = ["https://github.com/leanprover/lean4-nightly/releases/download/nightly-2021-09-22/lean-4.0.0-nightly-2021-09-22-darwin.zip"],
    sha256 = "e21d2f317af3eafc6da9499a3dcbcb2152e0df9ea5f2e23c75f1930bd80916c3",
    build_file = "@//:lean4.BUILD",
    strip_prefix = "lean-4.0.0-nightly-2021-09-22-darwin"
)