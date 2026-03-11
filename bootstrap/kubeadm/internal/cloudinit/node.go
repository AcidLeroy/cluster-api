/*
Copyright 2019 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package cloudinit

import (
	bootstrapv1 "sigs.k8s.io/cluster-api/api/bootstrap/kubeadm/v1beta2"
)

const (
	// ClusterConfigurationPath is the path where the control plane ClusterConfiguration
	// is written for worker nodes. Scripts running as preKubeadmCommands can read this
	// file to extract kubernetesVersion, networking, and other cluster-wide settings.
	ClusterConfigurationPath = "/run/cluster-api/cluster-configuration.yaml"
)

const (
	nodeCloudInit = `{{.Header}}
{{template "files" .WriteFiles}}
-   path: /run/kubeadm/kubeadm-join-config.yaml
    owner: root:root
    permissions: '0640'
    content: |
      ---
{{.JoinConfiguration | Indent 6}}
-   path: /run/cluster-api/placeholder
    owner: root:root
    permissions: '0640'
    content: "This placeholder file is used to create the /run/cluster-api sub directory in a way that is compatible with both Linux and Windows (mkdir -p /run/cluster-api does not work with Windows)"
{{- template "boot_commands" .BootCommands }}
runcmd:
{{- template "commands" .PreKubeadmCommands }}
  - {{ .KubeadmCommand }} && {{ .SentinelFileCommand }}
{{- template "commands" .PostKubeadmCommands }}
{{- template "ntp" .NTP }}
{{- template "users" .Users }}
{{- template "disk_setup" .DiskSetup}}
{{- template "fs_setup" .DiskSetup}}
{{- template "mounts" .Mounts}}
`
)

// NodeInput defines the context to generate a node user data.
type NodeInput struct {
	BaseUserData
	JoinConfiguration        string
	ClusterConfigurationYAML string
}

// NewNode returns the user data string to be used on a node instance.
func NewNode(input *NodeInput) ([]byte, error) {
	input.prepare()
	input.Header = cloudConfigHeader
	if input.ClusterConfigurationYAML != "" {
		ccFile := bootstrapv1.File{
			Path:        ClusterConfigurationPath,
			Owner:       "root:root",
			Permissions: "0644",
			Content:     input.ClusterConfigurationYAML,
		}
		input.WriteFiles = append([]bootstrapv1.File{ccFile}, input.WriteFiles...)
	}
	return generate("Node", nodeCloudInit, input)
}
