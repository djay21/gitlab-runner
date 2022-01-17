provider "kubernetes" {
  config_path    = "~/.kube/config"
  #config_context = "gitlab-runners"
}


resource "kubernetes_namespace" "gitlab" {
  metadata {
    name = "gitlab-runners"
  }
}


locals {
    namespace_name = "gitlab-runners"
  }


resource "kubernetes_persistent_volume_claim" "example" {
   
  metadata {
    name = "gitlab-runner-pvc"
    namespace = local.namespace_name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  #  volume_name = "${kubernetes_persistent_volume.example.metadata.0.name}"
  }
}


resource "kubernetes_deployment" "docker-dind-deployment" {
  depends_on = [
    kubernetes_persistent_volume_claim.example
  ]
  metadata {
    name = "docker-dind"
    namespace = local.namespace_name
    labels = {
      app = "docker-dind"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "docker-dind"
      }
    }

    template {
      metadata {
        labels = {
          app = "docker-dind"
        }
      }

      spec {
        
        volume {
        name = "docker-dind-data-vol"
        persistent_volume_claim {
            claim_name = "gitlab-runner-pvc"
            }
        }
        container {
          image = "docker:19.03-dind"
          name  = "docker-dind"
          security_context {
            privileged = true
          }
          volume_mount {
            name = "docker-dind-data-vol"
            mount_path = "/var/lib/docker/"
          }
          port {
              container_port = 2375
              host_port = 2375
          }
          env {
              name = "DOCKER_HOST"
              value= "tcp://0.0.0.0:2375"
          }
          env {
              name = "DOCKER_TLS_CERTDIR"
            value= ""       
       }  
          # resources {
          #   limits = {
          #   #   cpu    = "1"
          #     memory = "4Gi"
          #   }
            # requests = {
            # #   cpu    = "1"
            #   memory = "1Gi"
            # }
          # }

          }
        }
      }
    }
  }

resource "kubernetes_service" "docker-dind" {
  depends_on = [
    kubernetes_deployment.docker-dind-deployment
  ]
  metadata {
    name = "docker-dind"
    namespace = local.namespace_name
  }
  spec {
    selector = {
      app = kubernetes_deployment.docker-dind-deployment.spec.0.template.0.metadata[0].labels.app
    }
    port {
      port        = 2375
      target_port = 2375
    }

  }
}
