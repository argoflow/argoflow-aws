echo 'push changes to git repo with tag v0.4'

git add .
git commit -m 'debug changes'
git push
git tag v0.4 --delete
git tag v0.4
git push origin tag v0.4 --delete
git push origin tag v0.4

echo 'released new version'