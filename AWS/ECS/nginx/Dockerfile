FROM nginx:1.27-alpine

# Remove default config
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom config
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/default.conf /etc/nginx/conf.d/default.conf
COPY conf.d/heimdall.conf.disabled /etc/nginx/conf.d/heimdall.conf.disabled

# Prepare directories and switch to non-root
RUN touch /tmp/nginx.pid \
    && chown -R nginx:nginx /var/cache/nginx /var/log/nginx /tmp/nginx.pid /etc/nginx/conf.d \
    && chmod -R 755 /var/cache/nginx /var/log/nginx /etc/nginx/conf.d

USER nginx

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
