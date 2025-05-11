Git Conflicts
==============

##::When doing "git push" failed after local commit
----------------------------------------------------

git fetch origin
git merge origin/<branch-name>
	resolve the conflicts. open the file edit the 
	<<<<<<< HEAD
	Your changes
	=======
	Remote changes
	>>>>>>> origin/<branch-name>
git add .
git commit -m "commit messages"
git push origin <branch-name>


##::When doing "git pull" before local commit
---------------------------------------------
git stash
git pull
git stash pop
	resolve the conflicts. open the file edit the 
	<<<<<<< HEAD
	Your changes
	=======
	Remote changes
	>>>>>>> origin/<branch-name>
git add .
git commit -m "commit messages"
git push origin <branch-name>

