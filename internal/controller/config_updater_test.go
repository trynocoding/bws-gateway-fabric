package controller

import (
	"errors"
	"fmt"
	"testing"

	"github.com/go-logr/logr"
	. "github.com/onsi/gomega"
	"k8s.io/apimachinery/pkg/types"
	k8sEvents "k8s.io/client-go/tools/events"

	ngfAPI "github.com/nginx/nginx-gateway-fabric/v2/apis/v1alpha1"
	"github.com/nginx/nginx-gateway-fabric/v2/internal/controller/controllerfakes"
	"github.com/nginx/nginx-gateway-fabric/v2/internal/framework/helpers"
)

func TestUpdateControlPlane(t *testing.T) {
	t.Parallel()
	debugLogCfg := &ngfAPI.BwsGateway{
		Spec: ngfAPI.BwsGatewaySpec{
			Logging: &ngfAPI.Logging{
				Level: helpers.GetPointer(ngfAPI.ControllerLogLevelDebug),
			},
		},
	}

	invalidLevelConfig := &ngfAPI.BwsGateway{
		Spec: ngfAPI.BwsGatewaySpec{
			Logging: &ngfAPI.Logging{
				Level: helpers.GetPointer[ngfAPI.ControllerLogLevel]("invalid"),
			},
		},
	}

	logger := logr.Discard()
	nsname := types.NamespacedName{Namespace: "test", Name: "test"}

	tests := []struct {
		setLevelErr          error
		bwsGateway           *ngfAPI.BwsGateway
		name                 string
		expErrString         string
		expSetLevelCallCount int
		expEvent             bool
	}{
		{
			name:                 "change log level",
			bwsGateway:           debugLogCfg,
			expSetLevelCallCount: 1,
		},
		{
			name:                 "invalid log level",
			bwsGateway:           invalidLevelConfig,
			expErrString:         `Unsupported value: "invalid"`,
			expSetLevelCallCount: 0,
		},
		{
			name:                 "nil BwsGateway",
			bwsGateway:           nil,
			expEvent:             true,
			expSetLevelCallCount: 1,
		},
		{
			name:                 "set log level fails",
			bwsGateway:           debugLogCfg,
			setLevelErr:          errors.New("set level failed"),
			expErrString:         "set level failed",
			expSetLevelCallCount: 1,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			g := NewWithT(t)

			fakeLogSetter := &controllerfakes.FakeLogLevelSetter{
				SetLevelStub: func(_ string) error {
					return test.setLevelErr
				},
			}

			fakeEventRecorder := k8sEvents.NewFakeRecorder(1)

			err := updateControlPlane(test.bwsGateway, logger, fakeEventRecorder, nsname, fakeLogSetter)

			if test.expErrString != "" {
				g.Expect(err).To(HaveOccurred())
				g.Expect(err.Error()).To(ContainSubstring(test.expErrString))
			} else {
				g.Expect(err).ToNot(HaveOccurred())
			}

			if test.expEvent {
				g.Expect(fakeEventRecorder.Events).To(HaveLen(1))
				event := <-fakeEventRecorder.Events
				g.Expect(event).To(ContainSubstring("ResourceDeleted"))
			} else {
				g.Expect(fakeEventRecorder.Events).To(BeEmpty())
			}

			g.Expect(fakeLogSetter.SetLevelCallCount()).To(Equal(test.expSetLevelCallCount))
		})
	}
}

func TestValidateLogLevel(t *testing.T) {
	t.Parallel()
	validLevels := []ngfAPI.ControllerLogLevel{
		ngfAPI.ControllerLogLevelError,
		ngfAPI.ControllerLogLevelInfo,
		ngfAPI.ControllerLogLevelDebug,
	}

	invalidLevels := []ngfAPI.ControllerLogLevel{
		ngfAPI.ControllerLogLevel("invalid"),
		ngfAPI.ControllerLogLevel("high"),
		ngfAPI.ControllerLogLevel("warn"),
	}

	for _, level := range validLevels {
		t.Run(fmt.Sprintf("valid level %q", level), func(t *testing.T) {
			t.Parallel()
			g := NewWithT(t)

			g.Expect(validateLogLevel(level)).To(Succeed())
		})
	}

	for _, level := range invalidLevels {
		t.Run(fmt.Sprintf("invalid level %q", level), func(t *testing.T) {
			t.Parallel()
			g := NewWithT(t)

			g.Expect(validateLogLevel(level)).ToNot(Succeed())
		})
	}
}
