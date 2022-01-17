resource "google_container_node_pool" "gitlab-runner-pool" {
  project            = "gitlab-dev"
  name               = "gitlab-runners"
  location           = "us-west1-a"
  cluster            = "staging"
  initial_node_count = 1
  lifecycle { ignore_changes = ["initial_node_count"] }

  management {
    auto_repair  = true
    auto_upgrade = false
  }

  autoscaling {
    min_node_count = 2
    max_node_count = 6
  }

  node_config {
    preemptible  = true
    machine_type = "n1-standard-8"
    image_type   = "COS"

    labels = {
      "gitlab-runner-node" = "true"
    }

    taint {
      key    = "gitlab-runner"
      value  = "true"
      effect = "NO_SCHEDULE"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}

resource "kubernetes_namespace" "gitlab_runners_namespace" {
  metadata {
    name = "gitlab-runners"
  }
}

data "helm_repository" "gitlab" {
    name = "gitlab"
    url  = "https://charts.gitlab.io"
}

data "google_kms_secret" "registration-token" {
  crypto_key = "gitlab-runner/global/gitlab-runner-ring/gitlab-ci"
  ciphertext = "avcckhwdksjfnchwilkfsm/wedgfviwhcsgduycs"
}



resource "helm_release" "gitlab-runners" {
  depends_on = ["google_container_node_pool.gitlab-runner-pool", "kubernetes_namespace.gitlab_runners_namespace"]
  name       = "gitlab-runners"
  namespace  = "gitlab-runners"
  chart      = "gitlab/gitlab-runner"
  values = [
    <<VALUES
gitlabUrl: https://gitlab.com/
runnerRegistrationToken: ${data.google_kms_secret.registration-token.plaintext}
nodeSelector:
  gitlab-runner-node: "true"
tolerations:
  - effect: NoSchedule
    key: gitlab-runner
    operator: Exists
rbac:
  create: true
  rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "create", "delete"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["get", "create"]
  - apiGroups: [""]
    resources: ["pods/attach"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["secrets", "configmaps"]
    verbs: ["create", "update", "delete"]
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["create"]
runners:
  tags: gitlab-runner
  privileged: true
  config: |
    concurrent = 10
    [[runners]]
      [runners.kubernetes]
        namespace = "{{.Release.Namespace}}"
        image = "gitlab/gitlab-runner:alpine-v10.5.0"
        cpu_limit = "2"
        memory_limit = "4Gi"
        [runners.kubernetes.node_selector]
          gitlab-runner-node = "true"
        [runners.kubernetes.node_tolerations]
          "gitlab-runner=true" = "NoSchedule"
    [runners.cache]
      Type = "gcs"
      Path = "cache"
      Shared = false
      [runners.cache.gcs]
        AccessID = "abs@gcp.serviceaccount.com"
        PrivateKey = "----- BEGIN ... END----- "
        BucketName = "gitlab-runners-cache-bucket"
  
VALUES
  ]
}