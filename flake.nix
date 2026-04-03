{
  description = "A collection of project templates";

  outputs =
    { self }:
    {
      templates = {
        pi5 = {
          path = ./pi5;
          description = "A minimal Pi 5 SD Card Image Flake";
        };
        minimal = {
          path = ./minimal;
          description = "A minimal flake.";
        };
        tart-builders = {
          path = ./tart-builders;
          description = "Create VM Builders with Tart";
        };
        aws = {
          path = ./aws;
          description = "Create AWS CLI shell to help setup";
        };
        nur = {
          path = ./nur;
          description = "Use packages available on NUR";
        };
        local = {
          path = ./local;
          description = "Use local package default.nix";
        };
        go = {
          path = ./go;
          description = "Create a Go with parameterized golangci-lint v1 or v2";
        };
        python = {
          path = ./python;
          description = "Create python 3.12 environment with libraries";
        };
        shell = {
          path = ./shell;
          description = "Use packages available on nixpkgs";
        };
        docker = {
          path = ./docker;
          description = "Build Docker images with Nix";
        };
        server = {
          path = ./server;
          description = "Manage NixOS server remotely";
        };
        nixos-system = {
          path = ./nixos-system;
          description = "Minimal NixOS system for any architecture";
        };
        ipad = {
          path = ./ipad;
          description = "Self-contained NixOS for UTM SE on iPad";
        };
        dynatrace = {
          path = ./dynatrace;
          description = "Dynatrace app development with dtp-cli";
        };
        dynatrace-golangci-lint = {
          path = ./dynatrace-golangci-lint;
          description = "Create a shell with golangci-lint built from source for a specific version and exec string read from Dockerfile";
        };
        mikefarah = {
          path = ./mikefarah;
          description = "Create a shell with Mike Farah's jq and yq";
        };
        kubernetes = {
          path = ./kubernetes;
          description = "Kubernetes development environment with AWS EKS access";
        };
      };
      defaultTemplate = self.templates.shell;
    };
}
