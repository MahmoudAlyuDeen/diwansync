#!/bin/bash
# Remove all unused images, containers, networks, and build cache.
set -e

docker system prune -a -f