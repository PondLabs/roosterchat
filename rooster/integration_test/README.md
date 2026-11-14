# Integration Testing

To run unit tests, there are a few prerequisites.

 - Run Code Generation [scripts/codegen.dart](../scripts/codegen.dart)
 - Configure environment variables [. scripts/setup-env.sh](../scripts/setup-env.sh)
 - Start the synapse docker server [scripts/integration-server-synapse.sh](../scripts/integration-server-synapse.sh)
 - Configure synapse [scripts/integration-prepare-homeserver.sh](../scripts/integration-server-synapse.sh)

 If you have done all this you should be ready to test! [scripts/integration-test.sh](../scripts/integration-test.sh)

## Running the Linux app off screen

To run a Linux build without it showing on your screen, and to take
screenshots and videos of it, use
[scripts/headless-linux.sh](../scripts/headless-linux.sh). It starts the app
in a headless compositor of its own, with empty data folders, so it does not
open your accounts, and `--offline` keeps it off the network; the script's
header documents the commands.
