FROM julia:1.10.0-bookworm

ARG UID=1002
ARG GID=1002

RUN addgroup --gid $GID nonroot && \
    adduser  --uid $UID --gid $GID --disabled-password --gecos "" nonroot && \
    mkdir /env /julia && \
    chown nonroot:nonroot /env /julia && \
    chmod 777 /env /julia

USER nonroot
ENV JULIA_DEPOT_PATH=/julia

# to make binary compatible with older CPUs
ENV JULIA_CPU_TARGET="generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)"
RUN julia -e 'using Pkg; Pkg.activate("/env"); Pkg.add(["Minc2", "ArgParse"]); Pkg.add(url="https://github.com/vfonov/ROMEO.jl.git"); Pkg.add(url="https://github.com/vfonov/MriResearchTools.jl.git"); Pkg.add(url="https://github.com/vfonov/CLEARSWI.jl.git")'
COPY --chown=nonroot:nonroot entrypoint.sh /env/entrypoint.sh
COPY --chown=nonroot:nonroot clearswi_minc.jl /env/clearswi_minc.jl


# RUNNING as root to create a transient user for the container
USER root
RUN chmod a+w -R /env && \
    chmod a+w -R /julia && \
    find /julia -type d -exec chmod a+x '{}' '+' # HACK to make julia happy

USER nonroot
ENTRYPOINT ["/env/entrypoint.sh"]
