# Tab Groups: Design Notes

## Agreed behavior

- A tab group holds open tabs. Search restores groups and normal tabs at launch.
- A Settings switch enables tab groups. It starts off.
- A user creates a group from a tab's context menu.
- Groups work in the top tab row and the sidebar.
- Each space keeps its own groups with its own tabs. Switching spaces restores that space's group labels and open or closed state.
- A click on a group label expands its tabs in place. Several groups can stay open.
- A collapsed group can contain the active tab. Its page stays visible, and the group label shows that it is active.
- Search restores each group's open or closed state at launch.
- With the feature off, Search shows all tabs in one list and keeps saved group data.
- Search removes a group when its last tab leaves.
- Pinned tabs stay outside groups. Private tabs may join groups while the app runs.
- A new tab joins the active tab's group while that group is open. If the active tab is outside groups, or its group is closed, the new tab stays outside.
- A link opened in a new tab joins the source tab's group. A new private tab follows the New Tab rule for the current run.
- Dropping a tab onto a collapsed group adds the tab and opens the group. Dragging a tab into the normal tab area removes it from its group.
- A group menu has separate actions to ungroup its tabs and to close all its tabs.
- A group menu lets the user change its name and color.
- Creating a group from a tab makes it at that tab's position and opens it. Search gives it a default name and color at once.
- Dragging a group label moves the group and its tabs as one block.
- Pinning a grouped tab removes it from the group and moves it to the pinned block.
- Groups have one level. A group cannot contain another group.
- Users can choose from ten reusable group colors. There is no group count limit.
- A group can receive a default numbered name that starts with "Group".
- Search records whether a name was set by the user. Default names count only groups that the user has not named. They change to match the current order when those groups move or leave. A user-set name stays fixed, even if its text is "Group 1".
- At launch, a mixed group returns with its normal tabs. A group that held only private tabs does not return.
- If a keyboard command or the tab switcher selects a tab in a collapsed group, Search opens that group.
- ⌃Tab and ⌃⇧Tab visit tabs in collapsed groups and open the group when they select one.
- ⌘1–⌘9 count all tabs, including tabs in collapsed groups.
- Reopen Closed Tab returns a tab to its group when that group still exists. After Close Group, one Reopen Closed Tab restores the whole group and its normal tabs; private tabs stay closed.
- After Close Group, Search selects the nearest remaining tab. If no tab remains, it opens a blank tab.
- With the feature off, a new tab stays outside groups even when the active tab has saved group membership.

## Interaction details

- A drop onto a group label puts the tab at the end of that group. A drop between two tabs in an open group puts it at that position.
- A drop into another group moves the tab there. A drop into the normal tab area removes it from its group. An empty source group is removed.
- A new tab selected inside a collapsed group opens that group so the tab is visible.
- The New Tab command can create a normal tab while a group is closed, even when its active tab is blank.
- The group label shows its name and color. Color is not the only sign of group membership.
- Search assigns one of the ten colors when it creates a group. A user can change it from the group menu. Colors can repeat.
- A group with no user-set name uses its default name. Clearing a user-set name returns it to default naming.

## Code constraints

- The saved session currently has one flat tab list. Group data must load beside old session files without losing their tabs.
- Saved group data must record whether the name is user-set. The name text alone cannot tell Search which names may change.
- Private tab URLs, titles, and membership stay out of saved session data.
- Reopen Closed Tab currently holds one tab at a time. Closing and reopening a full group needs a separate closed-group record.
- Pinned tabs stay in their existing block. Grouping uses only normal tabs.
