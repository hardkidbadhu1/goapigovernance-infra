# Use the official Kong image as the base image
FROM kong:latest

# Switch to the root user to install our plugin
USER root

# Copy your custom Lua plugin into Kong’s plugin directory
COPY maintenance-toggle /Users/badhu/goapigovernance-infra/infra/maintenance-toggle

# (Optional) Ensure the plugin files have the correct ownership
RUN chown -R kong:kong /Users/badhu/goapigovernance-infra/infra/maintenance-toggle

# Enable your custom plugin by adding it to the KONG_PLUGINS environment variable.
ENV KONG_PLUGINS=bundled,maintenance-toggle

# Switch back to the kong user for safety
USER kong

# Start Kong when the container runs
CMD ["kong", "docker-start"]