# Beaker core tasks
_Beaker tasks which are essential to Beaker's operation._

Besides the custom tasks which Beaker users would write for a specific
testing scenario, there are a number of tasks which are distributed
and maintained along with Beaker. Among these,
the ``/distribution/check-install``, ``/distribution/install``, and 
``/distribution/reservesys`` tasks are
essential for Beaker's operation. The ``/distribution/inventory`` task is not
essential for Beaker's operation, but it is required for accurate
functioning of Beaker's ability to schedule jobs on test systems
meeting user specified hardware criteria. The
``/distribution/beaker/dogfood`` task runs Beaker's test suite (hence, the
name `dogfood`) and is perhaps only useful for meeting certain
specific requirements of the Beaker developers.

You can find more information about core tasks in [Beaker core task documentation](https://beaker-project.org/docs/user-guide/beaker-provided-tasks.html).
