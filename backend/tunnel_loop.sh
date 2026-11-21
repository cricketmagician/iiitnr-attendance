#!/bin/bash
while true; do
  ssh -p 443 -R0:localhost:8040 -o StrictHostKeyChecking=no -o ServerAliveInterval=15 a.pinggy.io
  sleep 2
done
