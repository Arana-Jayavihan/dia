{
  description = "Dia - A 1.6B parameter text-to-speech model for dialogue generation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        };

        # Use Python 3.11 for best compatibility with PyTorch
        python = pkgs.python311;

        # Nix store libraries
        nixLibs = with pkgs; [
          stdenv.cc.cc.lib
          zlib
          libsndfile
          ffmpeg
          portaudio
          libGL
          glib
        ];

        nixLibPath = pkgs.lib.makeLibraryPath nixLibs;

        # Full LD_LIBRARY_PATH including NVIDIA driver
        fullLibPath = "/run/opengl-driver/lib:${nixLibPath}";

        # FHS environment for maximum compatibility
        fhsEnv = pkgs.buildFHSEnv {
          name = "dia-fhs";
          targetPkgs = pkgs: with pkgs; [
            python
            python.pkgs.pip
            python.pkgs.virtualenv
            uv
            git
            ffmpeg
            libsndfile
            portaudio
            stdenv.cc.cc.lib
            zlib
            libGL
            glib
            xorg.libX11
            xorg.libXext
            xorg.libXrender
          ];
          runScript = "bash";
          profile = ''
            export LD_LIBRARY_PATH="${fullLibPath}:$LD_LIBRARY_PATH"
          '';
        };

      in
      {
        # Development shell - recommended for development
        devShells.default = pkgs.mkShell {
          name = "dia-dev";

          packages = with pkgs; [
            python
            uv
            git
            ffmpeg
            libsndfile
            portaudio
          ];

          buildInputs = nixLibs;

          shellHook = ''
            # NVIDIA driver libraries + Nix libraries
            export LD_LIBRARY_PATH="${fullLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

            # Create venv if it doesn't exist or is broken
            if [ ! -d ".venv" ] || [ ! -e ".venv/bin/python" ]; then
              echo "Creating virtual environment..."
              rm -rf .venv
              uv venv .venv --python ${python}/bin/python

              # Patch the activate script to include our LD_LIBRARY_PATH
              cat >> .venv/bin/activate << 'NIXEOF'

# Nix environment setup for CUDA
export LD_LIBRARY_PATH="${fullLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
NIXEOF
            fi

            source .venv/bin/activate

            # Check if dependencies are installed
            if ! python -c "import torch" 2>/dev/null; then
              echo "Installing dependencies with CUDA support..."
              uv pip install -e . "httpx[socks]" --extra-index-url https://download.pytorch.org/whl/cu126
            fi

            echo ""
            echo "══════════════════════════════════════════════════════════════"
            echo "  Dia TTS Development Environment"
            echo "══════════════════════════════════════════════════════════════"
            echo "  Python:     $(python --version)"
            echo ""
            python -c "import torch; print(f'  PyTorch:    {torch.__version__}'); print(f'  CUDA avail: {torch.cuda.is_available()}'); print(f'  GPU:        {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"N/A\"}')" 2>/dev/null || echo "  PyTorch:    (installing...)"
            echo "══════════════════════════════════════════════════════════════"
            echo ""
            echo "Commands:"
            echo "  python app.py     - Launch Gradio web UI"
            echo "  python cli.py     - Run CLI"
            echo ""
          '';
        };

        # FHS shell for maximum compatibility
        devShells.fhs = fhsEnv.env;

        # Packages
        packages = {
          fhs = fhsEnv;
        };

        # Apps for nix run
        apps = {
          default = {
            type = "app";
            program = toString (pkgs.writeShellScript "dia-gradio" ''
              export LD_LIBRARY_PATH="${fullLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
              cd ${./.}
              source .venv/bin/activate 2>/dev/null || {
                ${pkgs.uv}/bin/uv venv .venv --python ${python}/bin/python
                source .venv/bin/activate
                ${pkgs.uv}/bin/uv pip install -e . "httpx[socks]" --extra-index-url https://download.pytorch.org/whl/cu126
              }
              python app.py "$@"
            '');
          };

          cli = {
            type = "app";
            program = toString (pkgs.writeShellScript "dia-cli" ''
              export LD_LIBRARY_PATH="${fullLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
              cd ${./.}
              source .venv/bin/activate 2>/dev/null || {
                ${pkgs.uv}/bin/uv venv .venv --python ${python}/bin/python
                source .venv/bin/activate
                ${pkgs.uv}/bin/uv pip install -e . "httpx[socks]" --extra-index-url https://download.pytorch.org/whl/cu126
              }
              python cli.py "$@"
            '');
          };
        };
      }
    );
}
