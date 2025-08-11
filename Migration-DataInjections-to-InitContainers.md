# Migrating from Zarf Data Injections to OCI Image-Based Data Delivery

This guide explains how to migrate your Zarf deployment from the data injections feature to OCI image-based data delivery methods. Data injections is planned to be deprecated the current Zarf schema version and fully removed by Zarf v1.0.0. This is being done for several reasons: 

- **Host dependency**: Data injections shell out to `tar`, relying on host binaries that may not be available across environments
- **Poor User Experience**: The Data Injections workflow is difficult to use and adopt.
- **Better alternatives available**: OCI images provide a Kubernetes native solution for data delivery, and neatly fit into the Zarf delivery paradigm.

## Migration guide

This migration document provides a way to replace data injections with an init container and OCI images. In the future, we will recommend the new OCI volume source feature which will provide a simpler way to mount data from an image into a pod. OCI volume sources is a beta Kubernetes feature as of 1.33, and is not available by default. Read more about OCI volume sources in the enhancement proposal [4639-oci-volume-source](https://github.com/kubernetes/enhancements/tree/master/keps/sig-node/4639-oci-volume-source).

## Steps

### Step 1: Package Your Data in a Container Image

First, create a container image containing your data:

```dockerfile
FROM alpine:latest
COPY your-data-file /kiwix/your-data-file
```

Build and push this image:
```bash
docker build -t your-registry/your-data:tag .
docker push your-registry/your-data:tag
```

Some registries will not accept images over a certain size. In this case, you can load the image from the Docker Daemon. This can be slow, users are recommended to try out [this strategy for improving the speed of image loads](https://docs.zarf.dev/faq#how-can-i-improve-the-speed-of-loading-large-images-from-docker-on-zarf-package-create). Additionally, before Data Injections is removed Zarf allow users to load images directly from a tar file ([#2181](https://github.com/zarf-dev/zarf/issues/)), this will be significantly faster than Docker daemon pulls. 

### Step 2: Update zarf.yaml

**Before (Data Injections):**
```yaml
kind: ZarfPackageConfig
metadata:
  name: my-data-app
  version: 0.0.1

components:
  - name: kiwix-serve
    required: true
    images:
      - ghcr.io/kiwix/kiwix-serve:3.5.0-2
      - alpine:3.18
    dataInjections:
      - source: zim-data
        target:
          namespace: kiwix
          selector: app=kiwix-serve
          container: data-loader
          path: /data
        compress: true
```

**After (Init Container Strategy):**
```yaml
kind: ZarfPackageConfig
metadata:
  name: kiwix-init
  description: Demo Zarf init injection with Kiwix using container image
  version: 3.5.0

components:
  - name: kiwix-serve-init
    required: true
    images:
      - ghcr.io/kiwix/kiwix-serve:3.5.0-2
      - alpine:3.18
      - your-registry/your-data:tag  # Your container with your data file
```

**Key Changes:**
- Remove `dataInjections` section entirely
- Add your data container image to the `images` list

### Step 3: Update Deployment Manifest

**Before (Data Injections):**
```yaml
spec:
  template:
    spec:
      initContainers:
        - name: data-loader
          image: alpine:3.18
          command: ["sh", "-c"]
          args:
            - 'while [ ! -f /data/###ZARF_DATA_INJECTION_MARKER### ]; do echo "waiting for zarf data sync" && sleep 1; done; echo "we are done waiting!"'
          volumeMounts:
            - mountPath: /data
              name: data
```

**After (Init Container):**
```yaml
spec:
  template:
    spec:
      initContainers:
        - name: data-puller
          image: ghcr.io/austinabro321/zim-data:0.0.1
          command: ["sh", "-c"]
          args:
            - |
              cp /kiwix/devops.stackexchange.com_en_all_2023-05.zim /data/devops.stackexchange.com_en_all_2023-05.zim
              ls -la /data
              echo "Data initialization complete"
          volumeMounts:
            - mountPath: /data
              name: data
```

**Key Changes:**
- Replace data injection marker waiting logic with direct data copying
- Use your data container image instead a shell image

We recommend users migrate ahead of time.  