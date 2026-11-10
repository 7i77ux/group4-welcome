# group4-welcome

Source of the welcome page of Group 4: http://welcome.group4.umons

- `index.md`: the page, written in Markdown
- `deploy.sh`: publishes the page with nginx on the Welcome + mail VM and keeps it always on

## Deploy (on the Welcome + mail VM)

```
git clone https://github.com/7i77ux/group4-welcome
sudo sh group4-welcome/deploy.sh
```

## Update the page

Edit `index.md`, push, then on the VM:

```
cd group4-welcome && git pull && sudo sh deploy.sh
```
