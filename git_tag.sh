read -p 'enter commit message: ' commit_message

echo 'push changes to git repo with tag v0.4'

git add .
git commit -m '$commit_message'
git push
git tag v0.4 --delete
git tag v0.4
git push origin tag v0.4 --delete
git push origin tag v0.4

echo 'released new version'