package graph

import (
	"testing"

	"github.com/go-logr/logr"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/format"
	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	gatewayv1 "sigs.k8s.io/gateway-api/apis/v1"

	ngfAPIv1alpha2 "github.com/nginx/nginx-gateway-fabric/v2/apis/v1alpha2"
	"github.com/nginx/nginx-gateway-fabric/v2/internal/controller/state/conditions"
	"github.com/nginx/nginx-gateway-fabric/v2/internal/controller/state/graph/shared/secrets"
	"github.com/nginx/nginx-gateway-fabric/v2/internal/controller/state/validation"
	"github.com/nginx/nginx-gateway-fabric/v2/internal/controller/state/validation/validationfakes"
	"github.com/nginx/nginx-gateway-fabric/v2/internal/framework/helpers"
	"github.com/nginx/nginx-gateway-fabric/v2/internal/framework/kinds"
)

const (
	controllerName = "nginx"
	gcName         = "my-gateway-class"
)

var (
	plusSecret = &v1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: "ngf",
			Name:      "plus-secret",
		},
		Data: map[string][]byte{
			secrets.LicenseJWTKey: []byte("license"),
		},
	}
	convertedPlusSecret = map[types.NamespacedName][]PlusSecretFile{
		client.ObjectKeyFromObject(plusSecret): {
			{
				Type:      PlusReportJWTToken,
				Content:   []byte("license"),
				FieldName: secrets.LicenseJWTKey,
			},
		},
	}

	supportedHTTPGRPC = []gatewayv1.RouteGroupKind{
		{Kind: gatewayv1.Kind(kinds.HTTPRoute), Group: helpers.GetPointer[gatewayv1.Group](gatewayv1.GroupName)},
		{Kind: gatewayv1.Kind(kinds.GRPCRoute), Group: helpers.GetPointer[gatewayv1.Group](gatewayv1.GroupName)},
	}
	supportedTLS = []gatewayv1.RouteGroupKind{
		{Kind: gatewayv1.Kind(kinds.TLSRoute), Group: helpers.GetPointer[gatewayv1.Group](gatewayv1.GroupName)},
	}

	allowedRoutesHTTPGRPC = &gatewayv1.AllowedRoutes{
		Kinds: []gatewayv1.RouteGroupKind{
			{Kind: kinds.HTTPRoute, Group: helpers.GetPointer[gatewayv1.Group](gatewayv1.GroupName)},
			{Kind: kinds.GRPCRoute, Group: helpers.GetPointer[gatewayv1.Group](gatewayv1.GroupName)},
		},
	}
	allowedRoutesTLS = &gatewayv1.AllowedRoutes{
		Kinds: []gatewayv1.RouteGroupKind{
			{Kind: kinds.TLSRoute, Group: helpers.GetPointer[gatewayv1.Group](gatewayv1.GroupName)},
		},
	}

	experimentalFeaturesEnabled = false
)

func createGateway(name, namespace, bwsProxyName string, listeners []gatewayv1.Listener) *gatewayv1.Gateway {
	gateway := &gatewayv1.Gateway{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: namespace,
			Name:      name,
		},
		Spec: gatewayv1.GatewaySpec{
			GatewayClassName: gcName,
			Listeners:        listeners,
		},
	}

	if bwsProxyName != "" {
		gateway.Spec.Infrastructure = &gatewayv1.GatewayInfrastructure{
			ParametersRef: &gatewayv1.LocalParametersReference{
				Group: ngfAPIv1alpha2.GroupName,
				Kind:  kinds.BwsProxy,
				Name:  bwsProxyName,
			},
		}
	}

	return gateway
}

func createGatewayClass(name, controllerName, npName, npNamespace string) *gatewayv1.GatewayClass {
	if npName == "" {
		return &gatewayv1.GatewayClass{
			ObjectMeta: metav1.ObjectMeta{
				Name: name,
			},
			Spec: gatewayv1.GatewayClassSpec{
				ControllerName: gatewayv1.GatewayController(controllerName),
			},
		}
	}
	return &gatewayv1.GatewayClass{
		ObjectMeta: metav1.ObjectMeta{
			Name: name,
		},
		Spec: gatewayv1.GatewayClassSpec{
			ControllerName: gatewayv1.GatewayController(controllerName),
			ParametersRef: &gatewayv1.ParametersReference{
				Group:     ngfAPIv1alpha2.GroupName,
				Kind:      kinds.BwsProxy,
				Name:      npName,
				Namespace: helpers.GetPointer(gatewayv1.Namespace(npNamespace)),
			},
		},
	}
}

func convertedGatewayClass(
	gc *gatewayv1.GatewayClass,
	bwsProxy ngfAPIv1alpha2.BwsProxy,
	cond ...conditions.Condition,
) *GatewayClass {
	return &GatewayClass{
		Source: gc,
		BwsProxy: &BwsProxy{
			Source: &bwsProxy,
			Valid:  true,
		},
		Valid:      true,
		Conditions: cond,
	}
}

func createBwsProxy(name, namespace string, spec ngfAPIv1alpha2.BwsProxySpec) *ngfAPIv1alpha2.BwsProxy {
	return &ngfAPIv1alpha2.BwsProxy{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
		},
		Spec: spec,
	}
}

func convertedGateway(
	gw *gatewayv1.Gateway,
	bwsProxy *BwsProxy,
	effectiveNp *EffectiveBwsProxy,
	listeners []*Listener,
	conds []conditions.Condition,
) *Gateway {
	return &Gateway{
		Source:            gw,
		Valid:             true,
		BwsProxy:          bwsProxy,
		EffectiveBwsProxy: effectiveNp,
		Listeners:         listeners,
		Conditions:        conds,
		DeploymentName: types.NamespacedName{
			Name:      gw.Name + "-" + gcName,
			Namespace: gw.Namespace,
		},
	}
}

func createListener(
	name, hostname string,
	port int32,
	protocol gatewayv1.ProtocolType,
	tlsConfig *gatewayv1.ListenerTLSConfig,
	allowedRoutes *gatewayv1.AllowedRoutes,
) gatewayv1.Listener {
	listener := gatewayv1.Listener{
		Name:          gatewayv1.SectionName(name),
		Hostname:      (*gatewayv1.Hostname)(helpers.GetPointer(hostname)),
		Port:          port,
		Protocol:      protocol,
		AllowedRoutes: allowedRoutes,
	}

	if tlsConfig != nil {
		listener.TLS = tlsConfig
	}

	return listener
}

func convertListener(
	listener gatewayv1.Listener,
	gatewayNSName types.NamespacedName,
	secret *v1.Secret,
	supportedKinds []gatewayv1.RouteGroupKind,
	l7Route map[RouteKey]*L7Route,
	l4Route map[L4RouteKey]*L4Route,
) *Listener {
	l := &Listener{
		Name:           string(listener.Name),
		GatewayName:    gatewayNSName,
		Source:         listener,
		L4Routes:       l4Route,
		Routes:         l7Route,
		Valid:          true,
		SupportedKinds: supportedKinds,
		Attachable:     true,
	}

	if secret != nil {
		l.ResolvedSecrets = []types.NamespacedName{client.ObjectKeyFromObject(secret)}
	}
	return l
}

// Test_MultipleGateways_WithBwsProxy tests how nginx proxy config is inherited or overwritten
// when multiple gateways are present in the cluster.
func Test_MultipleGateways_WithBwsProxy(t *testing.T) {
	bwsProxyGlobal := createBwsProxy("nginx-proxy", testNs, ngfAPIv1alpha2.BwsProxySpec{
		DisableHTTP2: helpers.GetPointer(true),
	})

	bwsProxyGateway1 := createBwsProxy("nginx-proxy-gateway-1", testNs, ngfAPIv1alpha2.BwsProxySpec{
		Logging: &ngfAPIv1alpha2.NginxLogging{
			ErrorLevel: helpers.GetPointer(ngfAPIv1alpha2.NginxLogLevelDebug),
			AgentLevel: helpers.GetPointer(ngfAPIv1alpha2.AgentLogLevelDebug),
			AccessLog: &ngfAPIv1alpha2.NginxAccessLog{
				Format: helpers.GetPointer("$remote_addr - [$time_local] \"$request\" $status $body_bytes_sent"),
				Escape: helpers.GetPointer(ngfAPIv1alpha2.NginxAccessLogEscapeDefault),
			},
		},
	})

	bwsProxyGateway3 := createBwsProxy("nginx-proxy-gateway-3", "test2", ngfAPIv1alpha2.BwsProxySpec{
		Kubernetes: &ngfAPIv1alpha2.KubernetesSpec{
			Deployment: &ngfAPIv1alpha2.DeploymentSpec{
				Replicas: helpers.GetPointer(int32(3)),
			},
		},
		DisableHTTP2: helpers.GetPointer(false),
	})

	// Global BwsProxy with log format but no escape
	bwsProxyGlobalWithFormat := createBwsProxy("nginx-proxy-with-format", testNs, ngfAPIv1alpha2.BwsProxySpec{
		DisableHTTP2: helpers.GetPointer(true),
		Logging: &ngfAPIv1alpha2.NginxLogging{
			AccessLog: &ngfAPIv1alpha2.NginxAccessLog{
				Format: helpers.GetPointer("$remote_addr - [$time_local] \"$request\" $status"),
			},
		},
	})

	// Gateway BwsProxy that only sets escape (format comes from global)
	bwsProxyGatewayEscapeOnly := createBwsProxy("nginx-proxy-escape-only", testNs, ngfAPIv1alpha2.BwsProxySpec{
		Logging: &ngfAPIv1alpha2.NginxLogging{
			AccessLog: &ngfAPIv1alpha2.NginxAccessLog{
				Escape: helpers.GetPointer(ngfAPIv1alpha2.NginxAccessLogEscapeJSON),
			},
		},
	})

	gatewayClass := createGatewayClass(gcName, controllerName, "nginx-proxy", testNs)
	gatewayClassWithFormat := createGatewayClass(gcName, controllerName, "nginx-proxy-with-format", testNs)
	gateway1 := createGateway("gateway-1", testNs, "", []gatewayv1.Listener{})
	gateway2 := createGateway("gateway-2", testNs, "", []gatewayv1.Listener{})
	gateway3 := createGateway("gateway-3", "test2", "", []gatewayv1.Listener{})

	gateway1withNP := createGateway("gateway-1", testNs, "nginx-proxy-gateway-1", []gatewayv1.Listener{})
	gateway3withNP := createGateway("gateway-3", "test2", "nginx-proxy-gateway-3", []gatewayv1.Listener{})
	gatewayEscape := createGateway("gateway-escape", testNs, "nginx-proxy-escape-only", []gatewayv1.Listener{})

	gcConditions := []conditions.Condition{conditions.NewGatewayClassResolvedRefs()}

	tests := []struct {
		clusterState ClusterState
		expGraph     *Graph
		name         string
	}{
		{
			name: "gateway class with nginx proxy, multiple gateways inheriting settings from global nginx proxy",
			clusterState: ClusterState{
				GatewayClasses: map[types.NamespacedName]*gatewayv1.GatewayClass{
					client.ObjectKeyFromObject(gatewayClass): gatewayClass,
				},
				Gateways: map[types.NamespacedName]*gatewayv1.Gateway{
					client.ObjectKeyFromObject(gateway1): gateway1,
					client.ObjectKeyFromObject(gateway2): gateway2,
					client.ObjectKeyFromObject(gateway3): gateway3,
				},
				BwsProxies: map[types.NamespacedName]*ngfAPIv1alpha2.BwsProxy{
					client.ObjectKeyFromObject(bwsProxyGlobal): bwsProxyGlobal,
				},
				Secrets: map[types.NamespacedName]*v1.Secret{
					client.ObjectKeyFromObject(plusSecret): plusSecret,
				},
			},
			expGraph: &Graph{
				GatewayClass: convertedGatewayClass(gatewayClass, *bwsProxyGlobal, gcConditions...),
				Gateways: map[types.NamespacedName]*Gateway{
					client.ObjectKeyFromObject(gateway1): convertedGateway(
						gateway1,
						nil,
						&EffectiveBwsProxy{DisableHTTP2: helpers.GetPointer(true)},
						[]*Listener{},
						nil,
					),
					client.ObjectKeyFromObject(gateway2): convertedGateway(
						gateway2,
						nil,
						&EffectiveBwsProxy{DisableHTTP2: helpers.GetPointer(true)},
						[]*Listener{},
						nil,
					),
					client.ObjectKeyFromObject(gateway3): convertedGateway(
						gateway3,
						nil,
						&EffectiveBwsProxy{DisableHTTP2: helpers.GetPointer(true)},
						[]*Listener{},
						nil,
					),
				},
				ReferencedBwsProxies: map[types.NamespacedName]*BwsProxy{
					client.ObjectKeyFromObject(bwsProxyGlobal): {
						Source: bwsProxyGlobal,
						Valid:  true,
					},
				},
				Routes:      map[RouteKey]*L7Route{},
				L4Routes:    map[L4RouteKey]*L4Route{},
				PlusSecrets: convertedPlusSecret,
			},
		},
		{
			name: "gateway class with nginx proxy, multiple gateways with their own referenced nginx proxy",
			clusterState: ClusterState{
				GatewayClasses: map[types.NamespacedName]*gatewayv1.GatewayClass{
					client.ObjectKeyFromObject(gatewayClass): gatewayClass,
				},
				Gateways: map[types.NamespacedName]*gatewayv1.Gateway{
					client.ObjectKeyFromObject(gateway1withNP): gateway1withNP,
					client.ObjectKeyFromObject(gateway2):       gateway2,
					client.ObjectKeyFromObject(gateway3withNP): gateway3withNP,
				},
				BwsProxies: map[types.NamespacedName]*ngfAPIv1alpha2.BwsProxy{
					client.ObjectKeyFromObject(bwsProxyGlobal):   bwsProxyGlobal,
					client.ObjectKeyFromObject(bwsProxyGateway1): bwsProxyGateway1,
					client.ObjectKeyFromObject(bwsProxyGateway3): bwsProxyGateway3,
				},
				Secrets: map[types.NamespacedName]*v1.Secret{
					client.ObjectKeyFromObject(plusSecret): plusSecret,
				},
			},
			expGraph: &Graph{
				GatewayClass: convertedGatewayClass(gatewayClass, *bwsProxyGlobal, gcConditions...),
				Gateways: map[types.NamespacedName]*Gateway{
					client.ObjectKeyFromObject(gateway1withNP): convertedGateway(
						gateway1withNP,
						&BwsProxy{Source: bwsProxyGateway1, Valid: true},
						&EffectiveBwsProxy{
							Logging: &ngfAPIv1alpha2.NginxLogging{
								ErrorLevel: helpers.GetPointer(ngfAPIv1alpha2.NginxLogLevelDebug),
								AgentLevel: helpers.GetPointer(ngfAPIv1alpha2.AgentLogLevelDebug),
								AccessLog: &ngfAPIv1alpha2.NginxAccessLog{
									Format: helpers.GetPointer("$remote_addr - [$time_local] \"$request\" $status $body_bytes_sent"),
									Escape: helpers.GetPointer(ngfAPIv1alpha2.NginxAccessLogEscapeDefault),
								},
							},
							DisableHTTP2: helpers.GetPointer(true),
						},
						[]*Listener{},
						[]conditions.Condition{conditions.NewGatewayResolvedRefs()},
					),
					client.ObjectKeyFromObject(gateway2): convertedGateway(
						gateway2,
						nil,
						&EffectiveBwsProxy{DisableHTTP2: helpers.GetPointer(true)},
						[]*Listener{},
						nil,
					),
					client.ObjectKeyFromObject(gateway3withNP): convertedGateway(
						gateway3withNP,
						&BwsProxy{Source: bwsProxyGateway3, Valid: true},
						&EffectiveBwsProxy{
							Kubernetes: &ngfAPIv1alpha2.KubernetesSpec{
								Deployment: &ngfAPIv1alpha2.DeploymentSpec{
									Replicas: helpers.GetPointer(int32(3)),
								},
							},
							DisableHTTP2: helpers.GetPointer(false),
						},
						[]*Listener{},
						[]conditions.Condition{conditions.NewGatewayResolvedRefs()},
					),
				},
				ReferencedBwsProxies: map[types.NamespacedName]*BwsProxy{
					client.ObjectKeyFromObject(bwsProxyGlobal):   {Source: bwsProxyGlobal, Valid: true},
					client.ObjectKeyFromObject(bwsProxyGateway1): {Source: bwsProxyGateway1, Valid: true},
					client.ObjectKeyFromObject(bwsProxyGateway3): {Source: bwsProxyGateway3, Valid: true},
				},
				Routes:      map[RouteKey]*L7Route{},
				L4Routes:    map[L4RouteKey]*L4Route{},
				PlusSecrets: convertedPlusSecret,
			},
		},
		{
			name: "gateway class with log format, gateway overrides only escape setting",
			clusterState: ClusterState{
				GatewayClasses: map[types.NamespacedName]*gatewayv1.GatewayClass{
					client.ObjectKeyFromObject(gatewayClassWithFormat): gatewayClassWithFormat,
				},
				Gateways: map[types.NamespacedName]*gatewayv1.Gateway{
					client.ObjectKeyFromObject(gatewayEscape): gatewayEscape,
				},
				BwsProxies: map[types.NamespacedName]*ngfAPIv1alpha2.BwsProxy{
					client.ObjectKeyFromObject(bwsProxyGlobalWithFormat):  bwsProxyGlobalWithFormat,
					client.ObjectKeyFromObject(bwsProxyGatewayEscapeOnly): bwsProxyGatewayEscapeOnly,
				},
				Secrets: map[types.NamespacedName]*v1.Secret{
					client.ObjectKeyFromObject(plusSecret): plusSecret,
				},
			},
			expGraph: &Graph{
				GatewayClass: convertedGatewayClass(
					gatewayClassWithFormat,
					*bwsProxyGlobalWithFormat,
					gcConditions...,
				),
				Gateways: map[types.NamespacedName]*Gateway{
					client.ObjectKeyFromObject(gatewayEscape): convertedGateway(
						gatewayEscape,
						&BwsProxy{Source: bwsProxyGatewayEscapeOnly, Valid: true},
						&EffectiveBwsProxy{
							DisableHTTP2: helpers.GetPointer(true),
							Logging: &ngfAPIv1alpha2.NginxLogging{
								AccessLog: &ngfAPIv1alpha2.NginxAccessLog{
									// Format inherited from global, Escape overridden by gateway
									Format: helpers.GetPointer("$remote_addr - [$time_local] \"$request\" $status"),
									Escape: helpers.GetPointer(ngfAPIv1alpha2.NginxAccessLogEscapeJSON),
								},
							},
						},
						[]*Listener{},
						[]conditions.Condition{conditions.NewGatewayResolvedRefs()},
					),
				},
				ReferencedBwsProxies: map[types.NamespacedName]*BwsProxy{
					client.ObjectKeyFromObject(bwsProxyGlobalWithFormat):  {Source: bwsProxyGlobalWithFormat, Valid: true},
					client.ObjectKeyFromObject(bwsProxyGatewayEscapeOnly): {Source: bwsProxyGatewayEscapeOnly, Valid: true},
				},
				Routes:      map[RouteKey]*L7Route{},
				L4Routes:    map[L4RouteKey]*L4Route{},
				PlusSecrets: convertedPlusSecret,
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			g := NewWithT(t)
			format.MaxLength = 10000000

			fakePolicyValidator := &validationfakes.FakePolicyValidator{}

			result := BuildGraph(
				t.Context(),
				test.clusterState,
				controllerName,
				gcName,
				map[types.NamespacedName][]PlusSecretFile{
					client.ObjectKeyFromObject(plusSecret): {
						{
							Type:      PlusReportJWTToken,
							FieldName: secrets.LicenseJWTKey,
						},
					},
				},
				nil, // wafFetcher
				nil, // previousWAFBundles
				validation.Validators{
					HTTPFieldsValidator: &validationfakes.FakeHTTPFieldsValidator{},
					GenericValidator:    &validationfakes.FakeGenericValidator{},
					PolicyValidator:     fakePolicyValidator,
				},
				logr.Discard(),
				FeatureFlags{
					Experimental: experimentalFeaturesEnabled,
				},
			)

			// Verify ListenerFactory field separately since it's a complex internal struct
			// Directly comparing the ListenerFactory internal fields is unnecessary as it is tested
			// in the test file of where the ListenerFactory is defined.
			for gwKey, expectedGw := range test.expGraph.Gateways {
				actualGw, exists := result.Gateways[gwKey]
				g.Expect(exists).To(BeTrue())

				if expectedGw.Valid {
					g.Expect(actualGw.ListenerFactory).ToNot(BeNil())
				} else {
					g.Expect(actualGw.ListenerFactory).To(BeNil())
				}

				// Clear ListenerFactory from actual result for struct comparison
				actualGw.ListenerFactory = nil
			}

			g.Expect(helpers.Diff(test.expGraph, result)).To(BeEmpty())
		})
	}
}

// Test_MultipleGateways_WithListeners tests how listeners attach and interact with multiple gateways.
func Test_MultipleGateways_WithListeners(t *testing.T) {
	bwsProxyGlobal := createBwsProxy("nginx-proxy", testNs, ngfAPIv1alpha2.BwsProxySpec{
		DisableHTTP2: helpers.GetPointer(true),
	})
	gatewayClass := createGatewayClass(gcName, controllerName, "nginx-proxy", testNs)

	secretDiffNs := &v1.Secret{
		TypeMeta: metav1.TypeMeta{
			Kind: "Secret",
		},
		ObjectMeta: metav1.ObjectMeta{
			Namespace: "secret-ns",
			Name:      "secret",
		},
		Data: map[string][]byte{
			v1.TLSCertKey:       cert,
			v1.TLSPrivateKeyKey: key,
		},
		Type: v1.SecretTypeTLS,
	}

	rgSecretsToGateway := &gatewayv1.ReferenceGrant{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "rg-secret-to-gateway",
			Namespace: "secret-ns",
		},
		Spec: gatewayv1.ReferenceGrantSpec{
			From: []gatewayv1.ReferenceGrantFrom{
				{
					Group:     gatewayv1.GroupName,
					Kind:      kinds.Gateway,
					Namespace: gatewayv1.Namespace(testNs),
				},
			},
			To: []gatewayv1.ReferenceGrantTo{
				{
					Group: "core",
					Kind:  "Secret",
					Name:  helpers.GetPointer[gatewayv1.ObjectName]("secret"),
				},
			},
		},
	}

	tlsConfigDiffNsSecret := &gatewayv1.ListenerTLSConfig{
		Mode: helpers.GetPointer(gatewayv1.TLSModeTerminate),
		CertificateRefs: []gatewayv1.SecretObjectReference{
			{
				Kind:      helpers.GetPointer[gatewayv1.Kind]("Secret"),
				Name:      gatewayv1.ObjectName(secretDiffNs.Name),
				Namespace: helpers.GetPointer(gatewayv1.Namespace(secretDiffNs.Namespace)),
			},
		},
	}

	gateway1 := createGateway("gateway-1", testNs, "nginx-proxy", []gatewayv1.Listener{
		createListener(
			"listener-tls-mode-terminate",
			"*.example.com",
			443,
			gatewayv1.HTTPSProtocolType,
			tlsConfigDiffNsSecret,
			allowedRoutesHTTPGRPC,
		),
	})
	gateway2 := createGateway("gateway-2", testNs, "nginx-proxy", []gatewayv1.Listener{
		createListener(
			"listener-tls-mode-terminate",
			"*.example.com",
			443,
			gatewayv1.HTTPSProtocolType,
			tlsConfigDiffNsSecret,
			allowedRoutesHTTPGRPC,
		),
	})

	tlsConfigPassthrough := &gatewayv1.ListenerTLSConfig{
		Mode: helpers.GetPointer(gatewayv1.TLSModePassthrough),
	}

	secretSameNs := &v1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: "test",
			Name:      "secret",
		},
		Data: map[string][]byte{
			v1.TLSCertKey:       cert,
			v1.TLSPrivateKeyKey: key,
		},
		Type: v1.SecretTypeTLS,
	}

	gatewayTLSConfigSameNs := &gatewayv1.ListenerTLSConfig{
		Mode: helpers.GetPointer(gatewayv1.TLSModeTerminate),
		CertificateRefs: []gatewayv1.SecretObjectReference{
			{
				Kind:      helpers.GetPointer[gatewayv1.Kind]("Secret"),
				Name:      gatewayv1.ObjectName(secretSameNs.Name),
				Namespace: (*gatewayv1.Namespace)(&secretSameNs.Namespace),
			},
		},
	}

	// valid http, https and tls listeners
	listeners := []gatewayv1.Listener{
		createListener(
			"foo-listener-http",
			"foo.example.com",
			80,
			gatewayv1.HTTPProtocolType,
			nil,
			allowedRoutesHTTPGRPC,
		),
		createListener(
			"foo-listener-https",
			"tea.example.com",
			443,
			gatewayv1.HTTPSProtocolType,
			gatewayTLSConfigSameNs,
			allowedRoutesHTTPGRPC,
		),
		createListener(
			"listener-tls-mode-passthrough",
			"cafe.example.com",
			8443,
			gatewayv1.TLSProtocolType,
			tlsConfigPassthrough,
			allowedRoutesTLS,
		),
	}
	gatewayMultipleListeners1 := createGateway("gateway-multiple-listeners-1", testNs, "nginx-proxy", listeners)
	gatewayMultipleListeners2 := createGateway("gateway-multiple-listeners-2", testNs, "nginx-proxy", listeners)
	gatewayMultipleListeners3 := createGateway("gateway-multiple-listeners-3", testNs, "nginx-proxy", listeners)

	// valid TLS and https listener same port and hostname
	gatewayTLSSamePortHostname := createGateway(
		"gateway-tls-foo",
		testNs,
		"nginx-proxy",
		[]gatewayv1.Listener{
			createListener(
				"foo-listener-tls",
				"foo.example.com",
				443,
				gatewayv1.TLSProtocolType,
				tlsConfigPassthrough,
				allowedRoutesTLS,
			),
		},
	)

	gatewayHTTPSSamePortHostname := createGateway(
		"gateway-http-foo",
		testNs,
		"nginx-proxy",
		[]gatewayv1.Listener{
			createListener(
				"foo-listener-tls",
				"foo.example.com",
				443,
				gatewayv1.HTTPSProtocolType,
				gatewayTLSConfigSameNs,
				allowedRoutesHTTPGRPC,
			),
		},
	)

	tests := []struct {
		clusterState ClusterState
		expGraph     *Graph
		name         string
	}{
		{
			name: "multiple gateways with tls listeners, have reference grants to access the secret",
			clusterState: ClusterState{
				GatewayClasses: map[types.NamespacedName]*gatewayv1.GatewayClass{
					client.ObjectKeyFromObject(gatewayClass): gatewayClass,
				},
				Secrets: map[types.NamespacedName]*v1.Secret{
					client.ObjectKeyFromObject(plusSecret):   plusSecret,
					client.ObjectKeyFromObject(secretDiffNs): secretDiffNs,
				},
				Gateways: map[types.NamespacedName]*gatewayv1.Gateway{
					client.ObjectKeyFromObject(gateway1): gateway1,
					client.ObjectKeyFromObject(gateway2): gateway2,
				},
				BwsProxies: map[types.NamespacedName]*ngfAPIv1alpha2.BwsProxy{
					client.ObjectKeyFromObject(bwsProxyGlobal): bwsProxyGlobal,
				},
				ReferenceGrants: map[types.NamespacedName]*gatewayv1.ReferenceGrant{
					client.ObjectKeyFromObject(rgSecretsToGateway): rgSecretsToGateway,
				},
			},
			expGraph: &Graph{
				GatewayClass: convertedGatewayClass(gatewayClass, *bwsProxyGlobal, conditions.NewGatewayClassResolvedRefs()),
				Gateways: map[types.NamespacedName]*Gateway{
					client.ObjectKeyFromObject(gateway1): convertedGateway(
						gateway1,
						&BwsProxy{Source: bwsProxyGlobal, Valid: true},
						&EffectiveBwsProxy{DisableHTTP2: helpers.GetPointer(true)},
						[]*Listener{
							convertListener(
								gateway1.Spec.Listeners[0],
								client.ObjectKeyFromObject(gateway1),
								secretDiffNs,
								supportedHTTPGRPC,
								map[RouteKey]*L7Route{},
								map[L4RouteKey]*L4Route{},
							),
						},
						[]conditions.Condition{conditions.NewGatewayResolvedRefs()},
					),
					client.ObjectKeyFromObject(gateway2): convertedGateway(
						gateway2,
						&BwsProxy{Source: bwsProxyGlobal, Valid: true},
						&EffectiveBwsProxy{DisableHTTP2: helpers.GetPointer(true)},
						[]*Listener{
							convertListener(
								gateway2.Spec.Listeners[0],
								client.ObjectKeyFromObject(gateway2),
								secretDiffNs,
								supportedHTTPGRPC,
								map[RouteKey]*L7Route{},
								map[L4RouteKey]*L4Route{},
							),
						},
						[]conditions.Condition{conditions.NewGatewayResolvedRefs()},
					),
				},
				Routes:      map[RouteKey]*L7Route{},
				L4Routes:    map[L4RouteKey]*L4Route{},
				PlusSecrets: convertedPlusSecret,
				ReferencedBwsProxies: map[types.NamespacedName]*BwsProxy{
					client.ObjectKeyFromObject(bwsProxyGlobal): {Source: bwsProxyGlobal, Valid: true},
				},
				ReferencedSecrets: map[types.NamespacedName]*secrets.Secret{
					client.ObjectKeyFromObject(secretDiffNs): {
						Source: secretDiffNs,
						CertBundle: secrets.NewCertificateBundle(
							client.ObjectKeyFromObject(secretDiffNs),
							"Secret",
							&secrets.Certificate{
								TLSCert:       cert,
								TLSPrivateKey: key,
							}),
					},
				},
			},
		},
		{
			name: "valid http, https and tls listeners across multiple gateways with same port references," +
				"leads to no port conflict",
			clusterState: ClusterState{
				GatewayClasses: map[types.NamespacedName]*gatewayv1.GatewayClass{
					client.ObjectKeyFromObject(gatewayClass): gatewayClass,
				},
				Gateways: map[types.NamespacedName]*gatewayv1.Gateway{
					client.ObjectKeyFromObject(gatewayMultipleListeners1): gatewayMultipleListeners1,
					client.ObjectKeyFromObject(gatewayMultipleListeners2): gatewayMultipleListeners2,
					client.ObjectKeyFromObject(gatewayMultipleListeners3): gatewayMultipleListeners3,
				},
				BwsProxies: map[types.NamespacedName]*ngfAPIv1alpha2.BwsProxy{
					client.ObjectKeyFromObject(bwsProxyGlobal): bwsProxyGlobal,
				},
				Secrets: map[types.NamespacedName]*v1.Secret{
					client.ObjectKeyFromObject(plusSecret):   plusSecret,
					client.ObjectKeyFromObject(secretSameNs): secretSameNs,
				},
			},
			expGraph: &Graph{
				GatewayClass: convertedGatewayClass(gatewayClass, *bwsProxyGlobal, conditions.NewGatewayClassResolvedRefs()),
				Gateways: map[types.NamespacedName]*Gateway{
					client.ObjectKeyFromObject(gatewayMultipleListeners1): convertedGateway(
						gatewayMultipleListeners1,
						&BwsProxy{Source: bwsProxyGlobal, Valid: true},
						&EffectiveBwsProxy{DisableHTTP2: helpers.GetPointer(true)},
						[]*Listener{
							convertListener(
								gatewayMultipleListeners1.Spec.Listeners[0],
								client.ObjectKeyFromObject(gatewayMultipleListeners1),
								nil,
								supportedHTTPGRPC,
								map[RouteKey]*L7Route{},
								map[L4RouteKey]*L4Route{},
							),
							convertListener(
								gatewayMultipleListeners1.Spec.Listeners[1],
								client.ObjectKeyFromObject(gatewayMultipleListeners1),
								secretSameNs,
								supportedHTTPGRPC,
								map[RouteKey]*L7Route{},
								map[L4RouteKey]*L4Route{},
							),
							convertListener(
								gatewayMultipleListeners1.Spec.Listeners[2],
								client.ObjectKeyFromObject(gatewayMultipleListeners1),
								nil,
								supportedTLS,
								map[RouteKey]*L7Route{},
								map[L4RouteKey]*L4Route{},
							),
						},
						[]conditions.Condition{conditions.NewGatewayResolvedRefs()},
					),
					client.ObjectKeyFromObject(gatewayMultipleListeners2): convertedGateway(
						gatewayMultipleListeners2,
						&BwsProxy{Source: bwsProxyGlobal, Valid: true},
						&EffectiveBwsProxy{DisableHTTP2: helpers.GetPointer(true)},
						[]*Listener{
							convertListener(
								gatewayMultipleListeners2.Spec.Listeners[0],
								client.ObjectKeyFromObject(gatewayMultipleListeners2),
								nil,
								supportedHTTPGRPC,
								map[RouteKey]*L7Route{},
								map[L4RouteKey]*L4Route{},
							),
							convertListener(
								gatewayMultipleListeners2.Spec.Listeners[1],
								client.ObjectKeyFromObject(gatewayMultipleListeners2),
								secretSameNs,
								supportedHTTPGRPC,
								map[RouteKey]*L7Route{},
								map[L4RouteKey]*L4Route{},
							),
							convertListener(
								gatewayMultipleListeners2.Spec.Listeners[2],
								client.ObjectKeyFromObject(gatewayMultipleListeners2),
								nil,
								supportedTLS,
								map[RouteKey]*L7Route{},
								map[L4RouteKey]*L4Route{},
							),
						},
						[]conditions.Condition{conditions.NewGatewayResolvedRefs()},
					),
					client.ObjectKeyFromObject(gatewayMultipleListeners3): convertedGateway(
						gatewayMultipleListeners3,
						&BwsProxy{Source: bwsProxyGlobal, Valid: true},
						&EffectiveBwsProxy{DisableHTTP2: helpers.GetPointer(true)},
						[]*Listener{
							convertListener(
								gatewayMultipleListeners3.Spec.Listeners[0],
								client.ObjectKeyFromObject(gatewayMultipleListeners3),
								nil,
								supportedHTTPGRPC,
								map[RouteKey]*L7Route{},
								map[L4RouteKey]*L4Route{},
							),
							convertListener(
								gatewayMultipleListeners3.Spec.Listeners[1],
								client.ObjectKeyFromObject(gatewayMultipleListeners3),
								secretSameNs,
								supportedHTTPGRPC,
								map[RouteKey]*L7Route{},
								map[L4RouteKey]*L4Route{},
							),
							convertListener(
								gatewayMultipleListeners3.Spec.Listeners[2],
								client.ObjectKeyFromObject(gatewayMultipleListeners3),
								nil,
								supportedTLS,
								map[RouteKey]*L7Route{},
								map[L4RouteKey]*L4Route{},
							),
						},
						[]conditions.Condition{conditions.NewGatewayResolvedRefs()},
					),
				},
				Routes:      map[RouteKey]*L7Route{},
				L4Routes:    map[L4RouteKey]*L4Route{},
				PlusSecrets: convertedPlusSecret,
				ReferencedBwsProxies: map[types.NamespacedName]*BwsProxy{
					client.ObjectKeyFromObject(bwsProxyGlobal): {Source: bwsProxyGlobal, Valid: true},
				},
				ReferencedSecrets: map[types.NamespacedName]*secrets.Secret{
					client.ObjectKeyFromObject(secretSameNs): {
						Source: secretSameNs,
						CertBundle: secrets.NewCertificateBundle(
							client.ObjectKeyFromObject(secretSameNs),
							"Secret",
							&secrets.Certificate{
								TLSCert:       cert,
								TLSPrivateKey: key,
							}),
					},
				},
			},
		},
		{
			name: "valid tls and https listeners across multiple gateways with same port and hostname causes no conflict",
			clusterState: ClusterState{
				GatewayClasses: map[types.NamespacedName]*gatewayv1.GatewayClass{
					client.ObjectKeyFromObject(gatewayClass): gatewayClass,
				},
				Gateways: map[types.NamespacedName]*gatewayv1.Gateway{
					client.ObjectKeyFromObject(gatewayTLSSamePortHostname):   gatewayTLSSamePortHostname,
					client.ObjectKeyFromObject(gatewayHTTPSSamePortHostname): gatewayHTTPSSamePortHostname,
				},
				BwsProxies: map[types.NamespacedName]*ngfAPIv1alpha2.BwsProxy{
					client.ObjectKeyFromObject(bwsProxyGlobal): bwsProxyGlobal,
				},
				Secrets: map[types.NamespacedName]*v1.Secret{
					client.ObjectKeyFromObject(plusSecret):   plusSecret,
					client.ObjectKeyFromObject(secretSameNs): secretSameNs,
				},
			},
			expGraph: &Graph{
				GatewayClass: convertedGatewayClass(gatewayClass, *bwsProxyGlobal, conditions.NewGatewayClassResolvedRefs()),
				Gateways: map[types.NamespacedName]*Gateway{
					client.ObjectKeyFromObject(gatewayTLSSamePortHostname): convertedGateway(
						gatewayTLSSamePortHostname,
						&BwsProxy{Source: bwsProxyGlobal, Valid: true},
						&EffectiveBwsProxy{DisableHTTP2: helpers.GetPointer(true)},
						[]*Listener{
							convertListener(
								gatewayTLSSamePortHostname.Spec.Listeners[0],
								client.ObjectKeyFromObject(gatewayTLSSamePortHostname),
								nil,
								supportedTLS,
								map[RouteKey]*L7Route{},
								map[L4RouteKey]*L4Route{},
							),
						},
						[]conditions.Condition{conditions.NewGatewayResolvedRefs()},
					),
					client.ObjectKeyFromObject(gatewayHTTPSSamePortHostname): convertedGateway(
						gatewayHTTPSSamePortHostname,
						&BwsProxy{Source: bwsProxyGlobal, Valid: true},
						&EffectiveBwsProxy{DisableHTTP2: helpers.GetPointer(true)},
						[]*Listener{
							convertListener(
								gatewayHTTPSSamePortHostname.Spec.Listeners[0],
								client.ObjectKeyFromObject(gatewayHTTPSSamePortHostname),
								secretSameNs,
								supportedHTTPGRPC,
								map[RouteKey]*L7Route{},
								map[L4RouteKey]*L4Route{},
							),
						},
						[]conditions.Condition{conditions.NewGatewayResolvedRefs()},
					),
				},
				Routes:      map[RouteKey]*L7Route{},
				L4Routes:    map[L4RouteKey]*L4Route{},
				PlusSecrets: convertedPlusSecret,
				ReferencedBwsProxies: map[types.NamespacedName]*BwsProxy{
					client.ObjectKeyFromObject(bwsProxyGlobal): {Source: bwsProxyGlobal, Valid: true},
				},
				ReferencedSecrets: map[types.NamespacedName]*secrets.Secret{
					client.ObjectKeyFromObject(secretSameNs): {
						Source: secretSameNs,
						CertBundle: secrets.NewCertificateBundle(
							client.ObjectKeyFromObject(secretSameNs),
							"Secret",
							&secrets.Certificate{
								TLSCert:       cert,
								TLSPrivateKey: key,
							}),
					},
				},
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			g := NewWithT(t)
			format.MaxLength = 10000000

			fakePolicyValidator := &validationfakes.FakePolicyValidator{}

			result := BuildGraph(
				t.Context(),
				test.clusterState,
				controllerName,
				gcName,
				map[types.NamespacedName][]PlusSecretFile{
					client.ObjectKeyFromObject(plusSecret): {
						{
							Type:      PlusReportJWTToken,
							FieldName: secrets.LicenseJWTKey,
						},
					},
				},
				nil, // wafFetcher
				nil, // previousWAFBundles
				validation.Validators{
					HTTPFieldsValidator: &validationfakes.FakeHTTPFieldsValidator{},
					GenericValidator:    &validationfakes.FakeGenericValidator{},
					PolicyValidator:     fakePolicyValidator,
				},
				logr.Discard(),
				FeatureFlags{
					Experimental: experimentalFeaturesEnabled,
				},
			)

			// Verify ListenerFactory field separately since it's a complex internal struct
			// Directly comparing the ListenerFactory internal fields is unnecessary as it is tested
			// in the test file of where the ListenerFactory is defined.
			for gwKey, expectedGw := range test.expGraph.Gateways {
				actualGw, exists := result.Gateways[gwKey]
				g.Expect(exists).To(BeTrue())

				if expectedGw.Valid {
					g.Expect(actualGw.ListenerFactory).ToNot(BeNil())
				} else {
					g.Expect(actualGw.ListenerFactory).To(BeNil())
				}

				// Clear ListenerFactory from actual result for struct comparison
				actualGw.ListenerFactory = nil
			}

			g.Expect(helpers.Diff(test.expGraph, result)).To(BeEmpty())
		})
	}
}
