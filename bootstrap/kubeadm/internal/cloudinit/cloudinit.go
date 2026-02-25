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
	"bytes"
	"fmt"
	"text/template"

	"github.com/blang/semver/v4"
	"github.com/pkg/errors"

	bootstrapv1 "sigs.k8s.io/cluster-api/api/bootstrap/kubeadm/v1beta2"
)

const (
	standardJoinCommand = "kubeadm join --config /run/kubeadm/kubeadm-join-config.yaml %s"
	// sentinelFileCommand writes a file to /run/cluster-api to signal successful Kubernetes bootstrapping in a way that
	// works both for Linux and Windows OS.
	sentinelFileCommand = "echo success > /run/cluster-api/bootstrap-success.complete"
	// FetchKubeadmScriptCommandConst runs /tmp/fetch-kubeadm.sh if present (e.g. on custom node images). No-op if missing.
	// Exported for use by Ignition path which does not call prepare().
	// EXPERIMENTAL: Original line below; restore after experimental phase so we can see script output under CAPD (docker exec <container> cat /var/log/fetch-kubeadm.log).
	// FetchKubeadmScriptCommandConst = "[ -x /tmp/fetch-kubeadm.sh ] && /tmp/fetch-kubeadm.sh || true"
	FetchKubeadmScriptCommandConst = "[ -x /tmp/fetch-kubeadm.sh ] && /tmp/fetch-kubeadm.sh 2>&1 | tee /var/log/fetch-kubeadm.log || true"
	fetchKubeadmScriptCommand      = FetchKubeadmScriptCommandConst
	cloudConfigHeader         = `## template: jinja
#cloud-config
`
)

// BaseUserData is shared across all the various types of files written to disk.
type BaseUserData struct {
	Header                   string
	BootCommands             []string
	PreKubeadmCommands       []string
	PostKubeadmCommands      []string
	AdditionalFiles          []bootstrapv1.File
	WriteFiles               []bootstrapv1.File
	Users                    []bootstrapv1.User
	NTP                      *bootstrapv1.NTP
	DiskSetup                *bootstrapv1.DiskSetup
	Mounts                   []bootstrapv1.MountPoints
	ControlPlane             bool
	KubeadmCommand           string
	KubeadmVerbosity         string
	SentinelFileCommand       string
	FetchKubeadmScriptCommand string // Optional: run before kubeadm if present on node (e.g. /tmp/fetch-kubeadm.sh).
	RunFetchKubeadmScript     bool   // If true, run FetchKubeadmScriptCommand before kubeadm (worker join only).
	KubernetesVersion         semver.Version
}

func (input *BaseUserData) prepare() {
	input.Header = cloudConfigHeader
	input.WriteFiles = append(input.WriteFiles, input.AdditionalFiles...)
	input.KubeadmCommand = fmt.Sprintf(standardJoinCommand, input.KubeadmVerbosity)
	input.SentinelFileCommand = sentinelFileCommand
	input.FetchKubeadmScriptCommand = fetchKubeadmScriptCommand
}

func generate(kind string, tpl string, data interface{}) ([]byte, error) {
	tm := template.New(kind).Funcs(defaultTemplateFuncMap)
	if _, err := tm.Parse(filesTemplate); err != nil {
		return nil, errors.Wrap(err, "failed to parse files template")
	}

	if _, err := tm.Parse(bootCommandsTemplate); err != nil {
		return nil, errors.Wrap(err, "failed to parse boot commands template")
	}

	if _, err := tm.Parse(commandsTemplate); err != nil {
		return nil, errors.Wrap(err, "failed to parse commands template")
	}

	if _, err := tm.Parse(ntpTemplate); err != nil {
		return nil, errors.Wrap(err, "failed to parse ntp template")
	}

	if _, err := tm.Parse(usersTemplate); err != nil {
		return nil, errors.Wrap(err, "failed to parse users template")
	}

	if _, err := tm.Parse(diskSetupTemplate); err != nil {
		return nil, errors.Wrap(err, "failed to parse disk setup template")
	}

	if _, err := tm.Parse(fsSetupTemplate); err != nil {
		return nil, errors.Wrap(err, "failed to parse fs setup template")
	}

	if _, err := tm.Parse(mountsTemplate); err != nil {
		return nil, errors.Wrap(err, "failed to parse mounts template")
	}

	t, err := tm.Parse(tpl)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to parse %s template", kind)
	}

	var out bytes.Buffer
	if err := t.Execute(&out, data); err != nil {
		return nil, errors.Wrapf(err, "failed to generate %s template", kind)
	}

	return out.Bytes(), nil
}
