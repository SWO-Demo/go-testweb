1. Open https://console.aws.amazon.com/codesuite/codebuild/home - Create Project
2. In Project type, choose Runner project.

In Runner:
For Runner provider, choose GitHub.
For Runner location, choose Repository.
For Repository URL under Repository, choose https://github.com/user-name/repository-name.

4. In Environment:

Choose a supported Environment image and Compute. Note that you have the option to override the image and instance settings by using a label in your GitHub Actions workflow YAML. For more information, see Step 2: Update your GitHub Actions workflow YAML

In Buildspec:

Note that your buildspec will be ignored unless buildspec-override:true is added as a label. Instead, CodeBuild will override it to use commands that will setup the self-hosted runner.

5. Continue with the default values and then choose Create build project.

6. Open the GitHub console at https://github.com/user-name/repository-name/settings/hooks to verify that a webhook has been created and is enabled to deliver Workflow jobs events.

