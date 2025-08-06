FROM alpine:latest

# Create a 4GB random dummy file in a single layer
RUN dd if=/dev/urandom of=/dummyfile bs=10M count=1024