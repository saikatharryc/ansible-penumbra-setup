#!/bin/bash

# Check if the mounted volume exists
if [ -d "/penumbra-config" ]; then
    # Set permissions and ownership recursively
    echo "Volume is mounted - dont worry!"
else
    echo "Volume directory /penumbra-config does not exist."
fi

# Start your main application
exec "$@"
