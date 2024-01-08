FROM julia:1.10.0-bookworm

ARG UID=1002
ARG GID=1002

RUN addgroup --gid $GID nonroot && \
    adduser  --uid $UID --gid $GID --disabled-password --gecos "" nonroot && \
    mkdir /env /julia && \
    chown nonroot:nonroot /env /julia

USER nonroot
ENV JULIA_DEPOT_PATH=/julia
RUN julia -e 'using Pkg; Pkg.activate("/env"); Pkg.add(["Minc2", "ArgParse","MriResearchTools"]);Pkg.add(url="https://github.com/vfonov/CLEARSWI.jl.git")'
COPY --chown=nonroot:nonroot entrypoint.sh /env/entrypoint.sh
COPY --chown=nonroot:nonroot clearswi_minc.jl /env/clearswi_minc.jl

# #COPY --chown=nonroot:nonroot . /home/nonroot/app
# ENV HOME /home/nonroot
# WORKDIR /home/nonroot

#COPY entrypoint.sh /
#RUN  chmod u+x /entrypoint.sh
# RUNNING as root to create a transient user for the container
USER root

ENTRYPOINT ["/env/entrypoint.sh"]
