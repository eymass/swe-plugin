APP_PROD := app_name
APP_TEST := app_name_test

deploy:
	./tools/deploy/deploy.sh $(APP_PROD)

deploy-test:
	./tools/deploy/deploy.sh $(APP_TEST)
