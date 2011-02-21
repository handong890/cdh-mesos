/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.hadoop.test.system;

import java.io.File;
import java.io.IOException;
import java.security.PrivilegedExceptionAction;
import java.util.HashMap;
import java.util.List;
import java.util.ArrayList;
import java.util.Map;
import java.util.Properties;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.hadoop.io.Writable;
import org.apache.hadoop.security.UserGroupInformation;
import org.apache.hadoop.util.Shell.ShellCommandExecutor;
import org.apache.hadoop.fs.FileStatus;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.conf.Configuration;

/**
 * Default DaemonProtocolAspect which is used to provide default implementation
 * for all the common daemon methods. If a daemon requires more specialized
 * version of method, it is responsibility of the DaemonClient to introduce the
 * same in woven classes.
 * 
 */
public aspect DaemonProtocolAspect {

  private boolean DaemonProtocol.ready;
  
  @SuppressWarnings("unchecked")
  private HashMap<Object, List<ControlAction>> DaemonProtocol.actions = 
    new HashMap<Object, List<ControlAction>>();
  private static final Log LOG = LogFactory.getLog(
      DaemonProtocolAspect.class.getName());
  /**
   * Set if the daemon process is ready or not, concrete daemon protocol should
   * implement pointcuts to determine when the daemon is ready and use the
   * setter to set the ready state.
   * 
   * @param ready
   *          true if the Daemon is ready.
   */
  public void DaemonProtocol.setReady(boolean ready) {
    this.ready = ready;
  }

  /**
   * Checks if the daemon process is alive or not.
   * 
   * @throws IOException
   *           if daemon is not alive.
   */
  public void DaemonProtocol.ping() throws IOException {
  }

  /**
   * Checks if the daemon process is ready to accepting RPC connections after it
   * finishes initialization. <br/>
   * 
   * @return true if ready to accept connection.
   * 
   * @throws IOException
   */
  public boolean DaemonProtocol.isReady() throws IOException {
    return ready;
  }

  /**
   * Returns the process related information regarding the daemon process. <br/>
   * 
   * @return process information.
   * @throws IOException
   */
  public ProcessInfo DaemonProtocol.getProcessInfo() throws IOException {
    int activeThreadCount = Thread.activeCount();
    long currentTime = System.currentTimeMillis();
    long maxmem = Runtime.getRuntime().maxMemory();
    long freemem = Runtime.getRuntime().freeMemory();
    long totalmem = Runtime.getRuntime().totalMemory();
    Map<String, String> envMap = System.getenv();
    Properties sysProps = System.getProperties();
    Map<String, String> props = new HashMap<String, String>();
    for (Map.Entry entry : sysProps.entrySet()) {
      props.put((String) entry.getKey(), (String) entry.getValue());
    }
    ProcessInfo info = new ProcessInfoImpl(activeThreadCount, currentTime,
        freemem, maxmem, totalmem, envMap, props);
    return info;
  }

  public void DaemonProtocol.enable(List<Enum<?>> faults) throws IOException {
  }

  public void DaemonProtocol.disableAll() throws IOException {
  }

  public abstract Configuration DaemonProtocol.getDaemonConf()
    throws IOException;

  public FileStatus DaemonProtocol.getFileStatus(String path, boolean local) 
    throws IOException {
    Path p = new Path(path);
    FileSystem fs = getFS(p, local);
    p.makeQualified(fs);
    FileStatus fileStatus = fs.getFileStatus(p);
    return cloneFileStatus(fileStatus);
  }

  public FileStatus[] DaemonProtocol.listStatus(String path, boolean local) 
    throws IOException {
    Path p = new Path(path);
    FileSystem fs = getFS(p, local);
    FileStatus[] status = fs.listStatus(p);
    if (status != null) {
      FileStatus[] result = new FileStatus[status.length];
      int i = 0;
      for (FileStatus fileStatus : status) {
        result[i++] = cloneFileStatus(fileStatus);
      }
      return result;
    }
    return status;
  }

  /**
   * FileStatus object may not be serializable. Clone it into raw FileStatus 
   * object.
   */
  private FileStatus DaemonProtocol.cloneFileStatus(FileStatus fileStatus) {
    return new FileStatus(fileStatus.getLen(),
        fileStatus.isDir(),
        fileStatus.getReplication(),
        fileStatus.getBlockSize(),
        fileStatus.getModificationTime(),
        fileStatus.getAccessTime(),
        fileStatus.getPermission(),
        fileStatus.getOwner(),
        fileStatus.getGroup(),
        fileStatus.getPath());
  }

  private FileSystem DaemonProtocol.getFS(final Path path, final boolean local)
      throws IOException {
    FileSystem ret = null;
    try {
      ret = UserGroupInformation.getLoginUser().doAs (
          new PrivilegedExceptionAction<FileSystem>() {
            public FileSystem run() throws IOException {
              FileSystem fs = null;
              if (local) {
                fs = FileSystem.getLocal(getDaemonConf());
              } else {
                fs = path.getFileSystem(getDaemonConf());
              }
              return fs;
            }
          });
    } catch (InterruptedException ie) {
    }
    return ret;
  }
  
  @SuppressWarnings("unchecked")
  public ControlAction[] DaemonProtocol.getActions(Writable key) 
    throws IOException {
    synchronized (actions) {
      List<ControlAction> actionList = actions.get(key);
      if(actionList == null) {
        return new ControlAction[0];
      } else {
        return (ControlAction[]) actionList.toArray(new ControlAction[actionList
                                                                      .size()]);
      }
    }
  }


  @SuppressWarnings("unchecked")
  public void DaemonProtocol.sendAction(ControlAction action) 
      throws IOException {
    synchronized (actions) {
      List<ControlAction> actionList = actions.get(action.getTarget());
      if(actionList == null) {
        actionList = new ArrayList<ControlAction>();
        actions.put(action.getTarget(), actionList);
      }
      actionList.add(action);
    } 
  }
 
  @SuppressWarnings("unchecked")
  public boolean DaemonProtocol.isActionPending(ControlAction action) 
    throws IOException{
    synchronized (actions) {
      List<ControlAction> actionList = actions.get(action.getTarget());
      if(actionList == null) {
        return false;
      } else {
        return actionList.contains(action);
      }
    }
  }
  
  
  @SuppressWarnings("unchecked")
  public void DaemonProtocol.removeAction(ControlAction action) 
    throws IOException {
    synchronized (actions) {
      List<ControlAction> actionList = actions.get(action.getTarget());
      if(actionList == null) {
        return;
      } else {
        actionList.remove(action);
      }
    }
  }
  
  public void DaemonProtocol.clearActions() throws IOException {
    synchronized (actions) {
      actions.clear();
    }
  }

  public String DaemonProtocol.getFilePattern() {
    //We use the environment variable HADOOP_LOGFILE to get the
    //pattern to use in the search.
    String logDir = System.getenv("HADOOP_LOG_DIR");
    String daemonLogPattern = System.getenv("HADOOP_LOGFILE");
    if(daemonLogPattern == null && daemonLogPattern.isEmpty()) {
      return "*";
    }
    return  logDir+File.separator+daemonLogPattern+"*";
  }

  public int DaemonProtocol.getNumberOfMatchesInLogFile(String pattern,
      String[] list) throws IOException {
    StringBuffer filePattern = new StringBuffer(getFilePattern());    
    if(list != null){
      for(int i =0; i < list.length; ++i)
      {
        filePattern.append(" | grep -v " + list[i] );
      }
    }  
    String[] cmd =
        new String[] {
            "bash",
            "-c",
            "grep -c "
                + pattern + " " + filePattern
                + " | awk -F: '{s+=$2} END {print s}'" };    
    ShellCommandExecutor shexec = new ShellCommandExecutor(cmd);
    shexec.execute();
    String output = shexec.getOutput();
    return Integer.parseInt(output.replaceAll("\n", "").trim());
  }

  private String DaemonProtocol.user = null;
  
  public String DaemonProtocol.getDaemonUser() {
    return user;
  }
  
  public void DaemonProtocol.setUser(String user) {
    this.user = user;
  }
}

