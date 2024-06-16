FROM ghcr.io/penumbra-zone/penumbra:latest

COPY pd-init.sh /pd-init.sh
# RUN chmod +x /pd-init.sh
COPY nodes.json /nodes.json
# Copy volume initialization script
COPY init-volume.sh /init-volume.sh
# RUN chmod +x /init-volume.sh

USER penumbra
# Set entry point to run the volume initialization script
ENTRYPOINT ["/init-volume.sh"]
CMD ["/pd-init.sh"]
