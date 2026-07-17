package main

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	core "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"

	ngfAPI "github.com/nginx/nginx-gateway-fabric/v2/apis/v1alpha1"
)

var _ = Describe("BwsGateway", Ordered, Label("functional", "bwsGateway"), func() {
	var (
		ngfPodName string

		namespace        string
		bwsGatewayNsname types.NamespacedName

		files = []string{
			"nginxgateway/nginx-gateway.yaml",
		}
	)

	BeforeAll(func() {
		namespace = ngfNamespace
		bwsGatewayNsname = types.NamespacedName{Name: releaseName + "-config", Namespace: namespace}
	})

	getBwsGateway := func(nsname types.NamespacedName) (ngfAPI.BwsGateway, error) {
		ctx, cancel := context.WithTimeout(context.Background(), timeoutConfig.GetTimeout)
		defer cancel()

		var bwsGateway ngfAPI.BwsGateway

		if err := resourceManager.Get(ctx, nsname, &bwsGateway); err != nil {
			return bwsGateway, fmt.Errorf("failed to get bwsGateway: %w", err)
		}

		return bwsGateway, nil
	}

	verifyBwsGatewayConditions := func(ng ngfAPI.BwsGateway) error {
		if ng.Status.Conditions == nil {
			noConditionsErr := errors.New("bwsGateway has no conditions")
			GinkgoWriter.Printf("ERROR: %v\n", noConditionsErr)

			return noConditionsErr
		}

		if len(ng.Status.Conditions) != 1 {
			tooManyConditionsErr := fmt.Errorf(
				"expected bwsGateway to have only one condition, instead has %d conditions",
				len(ng.Status.Conditions),
			)
			GinkgoWriter.Printf("ERROR: %v\n", tooManyConditionsErr)

			return tooManyConditionsErr
		}

		return nil
	}

	getBwsGatewayCurrentObservedGeneration := func(ng ngfAPI.BwsGateway) (int64, error) {
		if err := verifyBwsGatewayConditions(ng); err != nil {
			return 0, err
		}

		return ng.Status.Conditions[0].ObservedGeneration, nil
	}

	verifyBwsGatewayStatus := func(ng ngfAPI.BwsGateway, expObservedGen int64) error {
		if err := verifyBwsGatewayConditions(ng); err != nil {
			return err
		}

		condition := ng.Status.Conditions[0]

		if condition.Type != "Valid" {
			invalidConditionTypeErr := fmt.Errorf(
				"expected bwsGateway condition type to be Valid, instead has type %s",
				condition.Type,
			)
			GinkgoWriter.Printf("ERROR: %v\n", invalidConditionTypeErr)

			return invalidConditionTypeErr
		}

		if condition.Reason != "Valid" {
			invalidReasonErr := fmt.Errorf("expected bwsGateway reason to be Valid, instead is %s", condition.Reason)
			GinkgoWriter.Printf("ERROR: %v\n", invalidReasonErr)

			return invalidReasonErr
		}

		if condition.ObservedGeneration != expObservedGen {
			observedGenerationErr := fmt.Errorf(
				"expected bwsGateway observed generation to be %d, instead is %d",
				expObservedGen,
				condition.ObservedGeneration,
			)
			GinkgoWriter.Printf("ERROR: %v\n", observedGenerationErr)
			return observedGenerationErr
		}

		return nil
	}

	getNGFPodName := func() (string, error) {
		podNames, err := resourceManager.GetReadyNGFPodNames(
			ngfNamespace,
			releaseName,
			timeoutConfig.GetStatusTimeout,
		)
		if err != nil {
			return "", err
		}

		if len(podNames) != 1 {
			tooManyPodsErr := fmt.Errorf("expected 1 pod name, got %d", len(podNames))
			GinkgoWriter.Printf("ERROR: %v\n", tooManyPodsErr)

			return "", tooManyPodsErr
		}

		return podNames[0], nil
	}

	AfterAll(func() {
		// re-apply BwsGateway crd to restore NGF instance for following functional tests
		Expect(resourceManager.ApplyFromFiles(files, namespace)).To(Succeed())

		Eventually(
			func() bool {
				ng, err := getBwsGateway(bwsGatewayNsname)
				if err != nil {
					return false
				}

				return verifyBwsGatewayStatus(ng, int64(1)) == nil
			}).WithTimeout(timeoutConfig.UpdateTimeout).
			WithPolling(500 * time.Millisecond).
			Should(BeTrue())
	})

	When("testing NGF on startup", func() {
		When("log level is set to debug", func() {
			It("outputs debug logs and the status is valid", func() {
				ngfPodName, err := getNGFPodName()
				Expect(err).ToNot(HaveOccurred())

				ng, err := getBwsGateway(bwsGatewayNsname)
				Expect(err).ToNot(HaveOccurred())

				Expect(verifyBwsGatewayStatus(ng, int64(1))).To(Succeed())

				Eventually(
					func() bool {
						logs, err := resourceManager.GetPodLogs(ngfNamespace, ngfPodName, &core.PodLogOptions{
							Container: "nginx-gateway",
						})
						if err != nil {
							return false
						}

						return strings.Contains(logs, "\"level\":\"debug\"")
					}).WithTimeout(timeoutConfig.GetTimeout).
					WithPolling(500 * time.Millisecond).
					Should(BeTrue())
			})
		})

		When("default log level is used", func() {
			It("only outputs info logs and the status is valid", func() {
				teardown(releaseName)

				cfg := getDefaultSetupCfg()
				cfg.debugLogLevel = false
				setup(cfg)

				ngfPodName, err := getNGFPodName()
				Expect(err).ToNot(HaveOccurred())

				Eventually(
					func() bool {
						ng, err := getBwsGateway(bwsGatewayNsname)
						if err != nil {
							return false
						}

						return verifyBwsGatewayStatus(ng, int64(1)) == nil
					}).WithTimeout(timeoutConfig.UpdateTimeout).
					WithPolling(500 * time.Millisecond).
					Should(BeTrue())

				Consistently(
					func() bool {
						logs, err := resourceManager.GetPodLogs(ngfNamespace, ngfPodName, &core.PodLogOptions{
							Container: "nginx-gateway",
						})
						if err != nil {
							return false
						}

						return !strings.Contains(logs, "\"level\":\"debug\"")
					}).WithTimeout(timeoutConfig.GetTimeout).
					WithPolling(500 * time.Millisecond).
					Should(BeTrue())
			})
		})
	})

	When("testing on an existing NGF instance", Ordered, func() {
		BeforeAll(func() {
			var err error
			ngfPodName, err = getNGFPodName()
			Expect(err).ToNot(HaveOccurred())
		})

		When("BwsGateway is updated", func() {
			It("captures the change, the status is valid, and the observed generation is incremented", func() {
				// previous test has left the log level at info, this test will change the log level to debug
				ng, err := getBwsGateway(bwsGatewayNsname)
				Expect(err).ToNot(HaveOccurred())

				gen, err := getBwsGatewayCurrentObservedGeneration(ng)
				Expect(err).ToNot(HaveOccurred())

				Expect(verifyBwsGatewayStatus(ng, gen)).To(Succeed())

				logs, err := resourceManager.GetPodLogs(ngfNamespace, ngfPodName, &core.PodLogOptions{
					Container: "nginx-gateway",
				})
				Expect(err).ToNot(HaveOccurred())

				Expect(logs).ToNot(ContainSubstring("\"level\":\"debug\""))

				Expect(resourceManager.ApplyFromFiles(files, namespace)).To(Succeed())

				Eventually(
					func() bool {
						ng, err := getBwsGateway(bwsGatewayNsname)
						if err != nil {
							return false
						}

						return verifyBwsGatewayStatus(ng, gen+1) == nil
					}).WithTimeout(timeoutConfig.UpdateTimeout).
					WithPolling(500 * time.Millisecond).
					Should(BeTrue())

				Eventually(
					func() bool {
						logs, err := resourceManager.GetPodLogs(ngfNamespace, ngfPodName, &core.PodLogOptions{
							Container: "nginx-gateway",
						})
						if err != nil {
							return false
						}

						return strings.Contains(logs, "\"level\":\"debug\"")
					}).WithTimeout(timeoutConfig.GetTimeout).
					WithPolling(500 * time.Millisecond).
					Should(BeTrue())
			})
		})

		When("BwsGateway is deleted", func() {
			It("captures the deletion and default values are used", func() {
				Expect(resourceManager.DeleteFromFiles(files, namespace)).To(Succeed())

				Eventually(
					func() error {
						_, err := getBwsGateway(bwsGatewayNsname)
						return err
					}).WithTimeout(timeoutConfig.DeleteTimeout).
					WithPolling(500 * time.Millisecond).
					Should(MatchError(ContainSubstring("failed to get bwsGateway")))

				Eventually(
					func() bool {
						logs, err := resourceManager.GetPodLogs(ngfNamespace, ngfPodName, &core.PodLogOptions{
							Container: "nginx-gateway",
						})
						if err != nil {
							return false
						}

						return strings.Contains(logs, "BwsGateway configuration was deleted; using defaults")
					}).WithTimeout(timeoutConfig.GetTimeout).
					WithPolling(500 * time.Millisecond).
					Should(BeTrue())

				events, err := resourceManager.GetEvents(namespace)
				Expect(err).ToNot(HaveOccurred())

				var foundBwsGatewayDeletionEvent bool
				for _, item := range events.Items {
					if item.Message == "BwsGateway configuration was deleted; using defaults" &&
						item.Type == "Warning" &&
						item.Reason == "ResourceDeleted" {
						foundBwsGatewayDeletionEvent = true
						break
					}
				}
				Expect(foundBwsGatewayDeletionEvent).To(BeTrue())
			})
		})
	})
})
