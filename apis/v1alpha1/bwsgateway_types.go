package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// +genclient
// +kubebuilder:object:root=true
// +kubebuilder:storageversion
// +kubebuilder:subresource:status
// +kubebuilder:resource:categories=bws-gateway-fabric
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// BwsGateway represents the dynamic configuration for a BWS Gateway Fabric control plane.
type BwsGateway struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	// BwsGatewaySpec defines the desired state of the BwsGateway.
	Spec BwsGatewaySpec `json:"spec"`

	// BwsGatewayStatus defines the state of the BwsGateway.
	Status BwsGatewayStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// BwsGatewayList contains a list of BwsGateways.
type BwsGatewayList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []BwsGateway `json:"items"`
}

// BwsGatewaySpec defines the desired state of the BwsGateway.
type BwsGatewaySpec struct {
	// Logging defines logging related settings for the control plane.
	//
	// +optional
	Logging *Logging `json:"logging,omitempty"`
}

// Logging defines logging related settings for the control plane.
type Logging struct {
	// Level defines the logging level.
	//
	// +optional
	// +kubebuilder:default=info
	Level *ControllerLogLevel `json:"level,omitempty"`
}

// ControllerLogLevel type defines the logging level for the control plane.
//
// +kubebuilder:validation:Enum=info;debug;error
type ControllerLogLevel string

const (
	// ControllerLogLevelInfo is the info level for control plane logging.
	ControllerLogLevelInfo ControllerLogLevel = "info"

	// ControllerLogLevelDebug is the debug level for control plane logging.
	ControllerLogLevelDebug ControllerLogLevel = "debug"

	// ControllerLogLevelError is the error level for control plane logging.
	ControllerLogLevelError ControllerLogLevel = "error"
)

// BwsGatewayStatus defines the state of the BwsGateway.
type BwsGatewayStatus struct {
	// +optional
	// +listType=map
	// +listMapKey=type
	// +kubebuilder:validation:MaxItems=8
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// BwsGatewayConditionType is a type of condition associated with an
// BwsGateway. This type should be used with the BwsGatewayStatus.Conditions field.
type BwsGatewayConditionType string

// BwsGatewayConditionReason defines the set of reasons that explain why a
// particular BwsGateway condition type has been raised.
type BwsGatewayConditionReason string

const (
	// BwsGatewayConditionValid is a condition that is true when the BwsGateway
	// configuration is syntactically and semantically valid.
	BwsGatewayConditionValid BwsGatewayConditionType = "Valid"

	// BwsGatewayReasonValid is a reason that is used with the "Valid" condition when the condition is True.
	BwsGatewayReasonValid BwsGatewayConditionReason = "Valid"

	// BwsGatewayReasonInvalid is a reason that is used with the "Valid" condition when the condition is False.
	BwsGatewayReasonInvalid BwsGatewayConditionReason = "Invalid"
)
