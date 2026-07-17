package v1alpha1

import "k8s.io/apimachinery/pkg/runtime"

// DeepCopyObject keeps the dormant upstream WAF types usable by internal compatibility code.
// WAFPolicy is intentionally not registered as a BWS CRD.
func (in *WAFPolicy) DeepCopyObject() runtime.Object {
	if in == nil {
		return nil
	}

	return in.DeepCopy()
}

// DeepCopyObject keeps the dormant upstream WAF list usable by internal compatibility code.
// WAFPolicy is intentionally not registered as a BWS CRD.
func (in *WAFPolicyList) DeepCopyObject() runtime.Object {
	if in == nil {
		return nil
	}

	return in.DeepCopy()
}
